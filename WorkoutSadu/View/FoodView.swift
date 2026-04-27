import SwiftUI
import SwiftData
import Charts

/// Обёртка для показа листа редактирования еды по тапу.
private struct EditMealItem: Identifiable {
    let id: UUID
    let meal: MealEntry
}

// MARK: - Food View (калории и приёмы пищи)

struct FoodView: View {
    @Environment(\.modelContext) private var context
    @Environment(GymBroManager.self) private var gymBro
    @Query(sort: \MealEntry.date) private var allMeals: [MealEntry]
    @Query(sort: \WaterEntry.date) private var allWater: [WaterEntry]
    @Query(sort: \Workout.date) private var workouts: [Workout]
    @Query private var profiles: [BodyProfile]

    private static let dailyWaterTargetML = 2000

    @State private var showAddMeal = false
    @State private var editingMeal: EditMealItem?
    @State private var caloriesDate: Date = Date()
    @State private var healthBurned: Int? = nil

    private var mealsForSelectedDay: [MealEntry] {
        let cal = Calendar.current
        return allMeals.filter { cal.isDate($0.date, inSameDayAs: caloriesDate) }
    }

    private var waterForSelectedDay: Int {
        let cal = Calendar.current
        return allWater
            .filter { cal.isDate($0.date, inSameDayAs: caloriesDate) }
            .reduce(0) { $0 + $1.amountML }
    }

    private var eatenToday: Int { mealsForSelectedDay.reduce(0) { $0 + $1.calories } }
    private var proteinToday: Double { mealsForSelectedDay.reduce(0) { $0 + $1.protein } }
    private var fatToday: Double { mealsForSelectedDay.reduce(0) { $0 + $1.fat } }
    private var carbsToday: Double { mealsForSelectedDay.reduce(0) { $0 + $1.carbs } }

    private var burnedToday: Int {
        if let hb = healthBurned { return hb }
        return CalorieCalculator.burnedOnDay(caloriesDate, workouts: workouts, profile: profiles.first)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        caloriesDatePicker
                        waterCard
                        caloriesBalanceCard
                        caloriesMacrosCard
                        caloriesMealListCard
                        caloriesWeeklyChart
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("ЕДА")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddMeal = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                    }
                }
            }
            .sheet(isPresented: $showAddMeal) { AddMealView(initialDate: caloriesDate) }
            .sheet(item: $editingMeal) { item in
                EditMealSheet(meal: item.meal)
            }
            .task(id: caloriesDate) {
                await refreshHealthCalories()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task { await refreshHealthCalories() }
            }
        }
        .onAppear {
            gymBro.screenContext = "Еда / калории"
        }
        .onDisappear { gymBro.screenContext = nil }
        .preferredColorScheme(.dark)
    }

    private func refreshHealthCalories() async {
        guard profiles.first?.healthKitEnabled == true else {
            healthBurned = nil
            return
        }
        let kcal = await HealthKitManager.shared.fetchActiveEnergyBurned(for: caloriesDate)
        healthBurned = Int(kcal)
    }

    // MARK: - Day picker

    private var caloriesDatePicker: some View {
        HStack {
            Button {
                caloriesDate = Calendar.current.date(byAdding: .day, value: -1, to: caloriesDate) ?? caloriesDate
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(Color(hex: "#6b6b80"))
            }
            Spacer()
            Text(caloriesDateLabel)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: "#f0f0f5"))
            Spacer()
            Button {
                let next = Calendar.current.date(byAdding: .day, value: 1, to: caloriesDate) ?? caloriesDate
                if next <= Date() { caloriesDate = next }
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color(hex: "#6b6b80"))
            }
            .disabled(Calendar.current.isDateInToday(caloriesDate))
        }
        .padding(18)
        .darkCard()
        .padding(.horizontal, 16)
    }

    private var caloriesDateLabel: String {
        if Calendar.current.isDateInToday(caloriesDate) { return "Сегодня" }
        if Calendar.current.isDateInYesterday(caloriesDate) { return "Вчера" }
        let f = DateFormatter(); f.dateFormat = "d MMMM"; f.locale = Locale(identifier: "ru_RU")
        return f.string(from: caloriesDate)
    }

    // MARK: - Water card

    private var waterCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "drop.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "#5b8cff"))
                Text("ВОДА")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .tracking(1)
                Spacer()
                Text("\(waterForSelectedDay) / \(Self.dailyWaterTargetML) мл")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "#1a1a24"))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "#5b8cff"))
                        .frame(width: min(geo.size.width, (Double(waterForSelectedDay) / Double(Self.dailyWaterTargetML)) * geo.size.width))
                }
            }
            .frame(height: 8)
            HStack(spacing: 10) {
                Button {
                    addWater(250)
                } label: {
                    Label("+250 мл", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: "#5b8cff"))
                }
                .buttonStyle(.plain)
                Button {
                    addWater(500)
                } label: {
                    Label("+500 мл", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: "#5b8cff"))
                }
                .buttonStyle(.plain)
            }
            if !Calendar.current.isDate(caloriesDate, inSameDayAs: Date()) {
                Text("Добавляется за \(caloriesDate, format: .dateTime.day().month(.abbreviated))")
                    .font(.caption)
                    .foregroundStyle(Color(hex: "#6b6b80"))
            }
        }
        .padding(16)
        .darkCard()
        .padding(.horizontal, 16)
    }
    private func addWater(_ ml: Int) {
        let entry = WaterEntry(date: caloriesDate, amountML: ml)
        context.insert(entry)
        if profiles.first?.healthKitEnabled == true {
            Task { await HealthKitManager.shared.saveWater(amountML: ml, date: caloriesDate) }
        }
        try? context.save()
    }

    // MARK: - Balance card

    private var caloriesBalanceCard: some View {
        let balance = eatenToday - burnedToday
        let target = CalorieCalculator.dailyTarget(profile: profiles.first)
        return VStack(spacing: 16) {
            if let target {
                HStack(spacing: 4) {
                    Text("Дневная норма:")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                    Text("~\(target) ккал")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: "#ffb830"))
                }
            }
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                    Text("\(eatenToday)")
                        .font(.custom("BebasNeue-Regular", size: 36))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    Text("Съедено")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hex: "#ffb830"))
                    Text("\(burnedToday)")
                        .font(.custom("BebasNeue-Regular", size: 36))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    Text("Сожжено")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Image(systemName: balance >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 18))
                        .foregroundStyle(balance >= 0 ? Color(hex: "#3aff9e") : Color(hex: "#5b8cff"))
                    Text("\(balance > 0 ? "+" : "")\(balance)")
                        .font(.custom("BebasNeue-Regular", size: 36))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    Text("Баланс")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .darkCard()
        .padding(.horizontal, 16)
    }

    // MARK: - Macros card

    private var caloriesMacrosCard: some View {
        VStack(spacing: 12) {
            sectionLabel("МАКРОСЫ")
            HStack(spacing: 16) {
                macroBar("Белки", proteinToday, Color(hex: "#5b8cff"))
                macroBar("Жиры", fatToday, Color(hex: "#ffb830"))
                macroBar("Углеводы", carbsToday, Color(hex: "#3aff9e"))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .darkCard()
        .padding(.horizontal, 16)
    }

    private func macroBar(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Text(String(format: "%.0f г", value))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(color)
            GeometryReader { geo in
                let maxVal: Double = 200
                let ratio = min(1.0, value / maxVal)
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(color)
                        .frame(height: geo.size.height * ratio)
                }
            }
            .frame(height: 60)
            .frame(maxWidth: 28)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Meals list

    private var caloriesMealListCard: some View {
        VStack(spacing: 0) {
            HStack {
                sectionLabel("ПРИЁМЫ ПИЩИ")
                Spacer()
                Button { showAddMeal = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                }
                .padding(.trailing, 16)
                .padding(.top, 10)
            }

            if mealsForSelectedDay.isEmpty {
                Text("Нет записей за этот день")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                let grouped = Dictionary(grouping: mealsForSelectedDay) { $0.mealType }
                let orderedTypes = MealType.allCases.filter { grouped[$0] != nil }

                ForEach(orderedTypes, id: \.rawValue) { type in
                    if let meals = grouped[type] {
                        HStack(spacing: 6) {
                            Image(systemName: type.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: "#ff5c3a"))
                            Text(type.rawValue.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .tracking(1)
                            Spacer()
                            Text("\(meals.reduce(0) { $0 + $1.calories }) ккал")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                        ForEach(meals.sorted { $0.date < $1.date }, id: \.id) { meal in
                            mealRow(meal)
                                .overlay(Divider().padding(.leading, 16), alignment: .bottom)
                        }
                    }
                }
            }

            Button { showAddMeal = true } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                    Text("Добавить еду")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                    Spacer()
                }
                .padding(16)
            }
        }
        .darkCard()
        .padding(.horizontal, 16)
    }

    private func mealRow(_ meal: MealEntry) -> some View {
        HStack {
            Button {
                editingMeal = EditMealItem(id: meal.id, meal: meal)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(meal.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: "#f0f0f5"))
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Text("Б \(String(format: "%.0f", meal.protein))")
                            Text("Ж \(String(format: "%.0f", meal.fat))")
                            Text("У \(String(format: "%.0f", meal.carbs))")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                        Text(mealTimeString(meal.date))
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                    }
                    Spacer()
                    Text("\(meal.calories) ккал")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                }
            }
            .buttonStyle(.plain)
            Button {
                context.delete(meal)
                try? context.save()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "#6b6b80").opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func mealTimeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: - Weekly chart

    private var caloriesWeeklyChart: some View {
        let points = caloriesWeeklyPoints
        return Group {
            if points.count >= 2 {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("НЕДЕЛЯ")
                    Chart(points, id: \.date) { p in
                        BarMark(
                            x: .value("День", p.date, unit: .day),
                            y: .value("Съедено", p.eaten)
                        )
                        .foregroundStyle(Color(hex: "#ff5c3a").opacity(0.7))
                        .cornerRadius(4)

                        if p.burned > 0 {
                            BarMark(
                                x: .value("День", p.date, unit: .day),
                                y: .value("Сожжено", -p.burned)
                            )
                            .foregroundStyle(Color(hex: "#ffb830").opacity(0.7))
                            .cornerRadius(4)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) {
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                        }
                    }
                    .chartYAxis {
                        AxisMarks {
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                            AxisValueLabel().foregroundStyle(Color(hex: "#6b6b80"))
                        }
                    }
                    .frame(height: 180)
                    .padding(.horizontal, 16)

                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: "#ff5c3a")).frame(width: 7, height: 7)
                            Text("Съедено").font(.system(size: 10)).foregroundStyle(Color(hex: "#6b6b80"))
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: "#ffb830")).frame(width: 7, height: 7)
                            Text("Сожжено").font(.system(size: 10)).foregroundStyle(Color(hex: "#6b6b80"))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
                .darkCard()
                .padding(.horizontal, 16)
            }
        }
    }

    private struct DayCaloriePoint {
        let date: Date
        let eaten: Int
        let burned: Int
    }

    private var caloriesWeeklyPoints: [DayCaloriePoint] {
        let cal = Calendar.current
        let profile = profiles.first
        return (0..<7).compactMap { offset -> DayCaloriePoint? in
            guard let day = cal.date(byAdding: .day, value: -6 + offset, to: cal.startOfDay(for: Date())) else { return nil }
            let dayMeals = allMeals.filter { cal.isDate($0.date, inSameDayAs: day) }
            let eaten = dayMeals.reduce(0) { $0 + $1.calories }
            let burned = CalorieCalculator.burnedOnDay(day, workouts: workouts, profile: profile)
            return DayCaloriePoint(date: day, eaten: eaten, burned: burned)
        }
    }

    // MARK: - Section label

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: "#6b6b80")).tracking(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}
