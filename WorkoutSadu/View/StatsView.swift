import SwiftUI
import SwiftData
import Charts

// MARK: - Data types

private struct WeekPoint: Identifiable {
    let id = UUID(); let weekStart: Date; let count: Int; let volume: Double
}
private struct BodyPartStat: Identifiable {
    let id = UUID(); let name: String; let sets: Int
}

// MARK: - Stats View (with Gamification tab)

struct StatsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.date) private var workouts: [Workout]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @Query(sort: \GeneratedQuest.order) private var allQuests: [GeneratedQuest]
    @Query private var profiles: [BodyProfile]
    @Query(sort: \MealEntry.date) private var allMeals: [MealEntry]

    @State private var tab: Int = 1   // 0=Статистика, 1=Квесты, 2=Рекорды, 3=Калории
    @State private var timeRange: TimeRange = .month
    @State private var calendarMonth: Date = Date()
    @State private var showAllPRs = false
    @State private var selectedDayWorkout: Workout?
    @State private var questsLoading = false
    @State private var showAddMeal = false
    @State private var caloriesDate: Date = Date()

    enum TimeRange: String, CaseIterable {
        case week="7д"; case month="Месяц"; case threeMonths="3М"; case year="Год"; case all="Всё"
        var startDate: Date? {
            let c = Calendar.current
            switch self {
            case .week:        return c.date(byAdding: .day, value: -7, to: .now)
            case .month:       return c.date(byAdding: .month, value: -1, to: .now)
            case .threeMonths: return c.date(byAdding: .month, value: -3, to: .now)
            case .year:        return c.date(byAdding: .year, value: -1, to: .now)
            case .all:         return nil
            }
        }
    }

    private var filtered: [Workout] {
        guard let s = timeRange.startDate else { return workouts }
        return workouts.filter { $0.date >= s }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                VStack(spacing: 0) {
                    // Tab bar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            let tabs = ["Статистика", "Квесты", "Рекорды", "Калории"]
                            ForEach(tabs.indices, id: \.self) { i in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { tab = i }
                                } label: {
                                    Text(tabs[i])
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(tab == i ? .black : Color(hex: "#6b6b80"))
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(tab == i ? Color(hex: "#ff5c3a") : Color.clear)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 12)

                    ScrollView {
                        if tab == 0 { statsContent }
                        else if tab == 1 { questsContent }
                        else if tab == 2 { recordsContent }
                        else { caloriesContent }
                    }
                }
            }
            .navigationTitle("ПРОГРЕСС")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedDayWorkout) { workout in
                WorkoutDetailView(workout: workout)
            }
            .sheet(isPresented: $showAddMeal) { AddMealView() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Stats tab

    var statsContent: some View {
        VStack(spacing: 14) {
            // Calendar
            calendarSection
            // Time range
            Picker("", selection: $timeRange) {
                ForEach(TimeRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            // Summary cards
            summaryCards
            // Charts
            if !weeklyPoints.isEmpty { activityChartView; volumeChartView }
            if !bodyPartStats.isEmpty { bodyPartChartView }
        }
        .padding(.bottom, 40)
    }

    // MARK: - Quests tab

    private var currentWeekQuests: [GeneratedQuest] {
        let weekId = GamificationManager.currentWeekId()
        return allQuests.filter { $0.weekId == weekId }
    }

    var questsContent: some View {
        VStack(spacing: 14) {
            xpLevelCard
            weeklyStreakCard
            sectionLabel("ПРОКАЧКА МЫШЦ")
            muscleGroupsCard
            sectionLabel("КВЕСТЫ НЕДЕЛИ")
            if questsLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color(hex: "#ff5c3a"))
                    Text("AI генерирует квесты...")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else if currentWeekQuests.isEmpty {
                VStack(spacing: 10) {
                    Text("Квесты не загружены")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                    Button {
                        loadQuests()
                    } label: {
                        Text("Сгенерировать")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color(hex: "#ff5c3a").opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(currentWeekQuests, id: \.id) { quest in
                    let progress = GamificationManager.questProgress(
                        targetType: quest.targetType,
                        targetValue: quest.targetValue,
                        workouts: workouts,
                        context: context
                    )
                    let ratio = quest.targetValue > 0 ? min(1.0, progress.current / quest.targetValue) : 0
                    challengeCard(
                        icon: quest.icon,
                        color: Color(hex: quest.colorHex),
                        title: quest.title,
                        sub: quest.subtitle,
                        progress: ratio,
                        current: progress.label,
                        xp: quest.isCompleted ? "✅ +\(quest.xp) XP" : "+\(quest.xp) XP",
                        accentColor: Color(hex: quest.colorHex)
                    )
                    .onAppear { markQuestIfCompleted(quest, current: progress.current) }
                }
            }
        }
        .padding(.bottom, 40)
        .onAppear { loadQuests() }
        .onChange(of: workouts.count) { _, _ in syncQuestCompletion() }
    }

    private func markQuestIfCompleted(_ quest: GeneratedQuest, current: Double) {
        if !quest.isCompleted && current >= quest.targetValue {
            quest.isCompleted = true
            try? context.save()
        }
    }

    private func syncQuestCompletion() {
        for quest in currentWeekQuests {
            let progress = GamificationManager.questProgress(
                targetType: quest.targetType,
                targetValue: quest.targetValue,
                workouts: workouts,
                context: context
            )
            markQuestIfCompleted(quest, current: progress.current)
        }
    }

    private func loadQuests() {
        guard currentWeekQuests.isEmpty, !questsLoading else { return }
        questsLoading = true
        Task {
            await GamificationManager.generateQuests(
                workouts: workouts,
                profile: profiles.first,
                context: context
            )
            await MainActor.run { questsLoading = false }
        }
    }

    // MARK: - Records tab

    var recordsContent: some View {
        VStack(spacing: 14) {
            sectionLabel("ЛИЧНЫЕ РЕКОРДЫ")
            AllPRsInlineView()
        }
        .padding(.bottom, 40)
    }

    // MARK: - Calories tab

    private var mealsForSelectedDay: [MealEntry] {
        let cal = Calendar.current
        return allMeals.filter { cal.isDate($0.date, inSameDayAs: caloriesDate) }
    }

    private var eatenToday: Int { mealsForSelectedDay.reduce(0) { $0 + $1.calories } }
    private var proteinToday: Double { mealsForSelectedDay.reduce(0) { $0 + $1.protein } }
    private var fatToday: Double { mealsForSelectedDay.reduce(0) { $0 + $1.fat } }
    private var carbsToday: Double { mealsForSelectedDay.reduce(0) { $0 + $1.carbs } }

    private var burnedToday: Int {
        CalorieCalculator.burnedOnDay(caloriesDate, workouts: workouts, profile: profiles.first)
    }

    var caloriesContent: some View {
        VStack(spacing: 14) {
            caloriesDatePicker
            caloriesBalanceCard
            caloriesMacrosCard
            caloriesMealListCard
            caloriesWeeklyChart
        }
        .padding(.bottom, 40)
    }

    // MARK: Day picker

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

    // MARK: Balance card

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

    // MARK: Macros card

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

    // MARK: Meals list

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

                        ForEach(meals, id: \.id) { meal in
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
            }
            Spacer()
            Text("\(meal.calories) ккал")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "#ff5c3a"))
            Button { context.delete(meal); try? context.save() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "#6b6b80").opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Weekly chart

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

    // MARK: - XP Level card

    var xpLevelCard: some View {
        let xp = GamificationManager.xpTotal(workouts: workouts, quests: allQuests)
        let info = GamificationManager.level(xp: xp)
        return VStack(spacing: 14) {
            HStack(alignment: .top) {
                HStack(spacing: 12) {
                    Text(info.emoji)
                        .font(.system(size: 28))
                        .frame(width: 50, height: 50)
                        .background(Color(hex: "#ff5c3a").opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#ff5c3a").opacity(0.3), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("УРОВЕНЬ \(info.level) — \(info.name.uppercased())")
                            .font(.custom("BebasNeue-Regular", size: 18))
                            .foregroundStyle(Color(hex: "#f0f0f5"))
                        Text("Следующий уровень · осталось \(info.xpForNext - xp) XP")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(xp)").font(.custom("BebasNeue-Regular", size: 30)).foregroundStyle(Color(hex: "#ff5c3a"))
                    Text("XP").font(.system(size: 10)).foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07)).frame(height: 8)
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: "#ff5c3a"), Color(hex: "#ffb830")], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * info.progressInLevel, height: 8)
                }
            }
            .frame(height: 8)
            HStack {
                Text("\(info.xpAtStart) XP").font(.system(size: 10)).foregroundStyle(Color(hex: "#6b6b80"))
                Spacer()
                Text("\(xp) / \(info.xpForNext) XP").font(.system(size: 10)).foregroundStyle(Color(hex: "#6b6b80"))
                Spacer()
                Text("\(info.xpForNext) XP").font(.system(size: 10)).foregroundStyle(Color(hex: "#6b6b80"))
            }
        }
        .padding(18)
        .darkCard()
        .padding(.horizontal, 16)
    }

    // MARK: - Weekly Streak card

    var weeklyStreakCard: some View {
        let streak = GamificationManager.weeklyStreak(workouts: workouts)
        return VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("СЕРИЯ НЕДЕЛЬ")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "#6b6b80")).tracking(1)
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(streak.current)")
                            .font(.custom("BebasNeue-Regular", size: 52))
                            .foregroundStyle(Color(hex: "#ffb830"))
                        Text("нед.")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                    }
                    Text("Рекорд: \(streak.record) недель")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Цель: \(streak.goalPerWeek) тр/нед")
                        .font(.system(size: 11)).foregroundStyle(Color(hex: "#6b6b80"))
                    Text("\(streak.completedThisWeek)/\(streak.goalPerWeek)")
                        .font(.custom("BebasNeue-Regular", size: 30))
                        .foregroundStyle(streak.completedThisWeek >= streak.goalPerWeek ? Color(hex: "#3aff9e") : Color(hex: "#ff5c3a"))
                    Text("эта неделя")
                        .font(.system(size: 10)).foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
            // Week dots
            HStack(spacing: 6) {
                ForEach(Array(streak.weekHistory.enumerated()), id: \.0) { _, done in
                    weekDot(done: done, label: "")
                }
                weekDot(current: true, label: "сейчас")
            }
            // Hint
            if streak.completedThisWeek < streak.goalPerWeek {
                let needed = streak.goalPerWeek - streak.completedThisWeek
                Text("Осталось \(needed) тр. чтобы закрыть неделю и продлить серию")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "#ffb830").opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#ffb830").opacity(0.15), lineWidth: 1))
            }
        }
        .padding(18)
        .darkCard(accentBorder: Color(hex: "#ffb830").opacity(0.25))
        .padding(.horizontal, 16)
    }

    private func weekDot(done: Bool = false, current: Bool = false, label: String) -> some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(current ? Color(hex: "#ff5c3a").opacity(0.15) : done ? Color(hex: "#ffb830").opacity(0.18) : Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                        current ? Color(hex: "#ff5c3a").opacity(0.4) : done ? Color(hex: "#ffb830").opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1))
                Text(current ? "⏳" : done ? "✅" : "·")
                    .font(.system(size: current || done ? 14 : 16))
            }
            .frame(height: 34)
            if !label.isEmpty {
                Text(label).font(.system(size: 8)).foregroundStyle(Color(hex: "#6b6b80"))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Muscle groups card

    var muscleGroupsCard: some View {
        let statuses = GamificationManager.muscleStatuses(workouts: workouts)
        return VStack(spacing: 12) {
            HStack {
                Text("Скользящее окно")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                Spacer()
                Text("последние 10 дней")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#ffb830"))
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(statuses) { s in
                    muscleCell(s)
                }
            }
            // Legend
            HStack(spacing: 12) {
                legendDot(color: Color(hex: "#3aff9e"), label: "В окне")
                legendDot(color: Color(hex: "#ffb830"), label: "Скоро выпадет")
                legendDot(color: Color(hex: "#ff5c3a"), label: "Выпало")
            }
            .font(.system(size: 10)).foregroundStyle(Color(hex: "#6b6b80"))
            // Warning
            if let warn = statuses.first(where: { $0.state == .warning }) {
                HStack(spacing: 6) {
                    Text("💡").font(.system(size: 13))
                    Text("\(warn.name) \(warn.label) — скоро выпадет из зачёта")
                        .font(.system(size: 11)).foregroundStyle(Color(hex: "#6b6b80"))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#ffb830").opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#ffb830").opacity(0.15), lineWidth: 1))
            }
        }
        .padding(18)
        .darkCard()
        .padding(.horizontal, 16)
    }

    private func muscleCell(_ s: MuscleGroupStatus) -> some View {
        let borderColor: Color = s.state == .done ? Color(hex: "#3aff9e").opacity(0.35)
            : s.state == .warning ? Color(hex: "#ffb830").opacity(0.35) : Color(hex: "#ff5c3a").opacity(0.3)
        let statusColor: Color = s.state == .done ? Color(hex: "#3aff9e")
            : s.state == .warning ? Color(hex: "#ffb830") : Color(hex: "#ff5c3a")

        return VStack(spacing: 4) {
            Text(s.emoji).font(.system(size: 24))
            Text(s.name).font(.system(size: 10, weight: .medium)).foregroundStyle(Color(hex: "#6b6b80"))
            Text(s.label).font(.system(size: 10, weight: .bold)).foregroundStyle(statusColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(hex: "#1e1e28"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 1))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }

    // MARK: - Challenge card

    private func challengeCard(icon: String, color: Color, title: String, sub: String, progress: Double, current: String, xp: String, accentColor: Color) -> some View {
        HStack(spacing: 14) {
            Text(icon)
                .font(.system(size: 22))
                .frame(width: 46, height: 46)
                .background(accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: "#f0f0f5"))
                Text(sub).font(.system(size: 11)).foregroundStyle(Color(hex: "#6b6b80")).lineLimit(2)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.06)).frame(height: 5)
                        Capsule().fill(accentColor).frame(width: geo.size.width * progress, height: 5)
                    }
                }
                .frame(height: 5)
                HStack {
                    Text(current).font(.system(size: 10)).foregroundStyle(Color(hex: "#6b6b80"))
                    Spacer()
                    Text(xp).font(.system(size: 11, weight: .bold)).foregroundStyle(accentColor)
                }
            }
        }
        .padding(16)
        .darkCard(accentBorder: accentColor.opacity(0.25))
        .padding(.horizontal, 16)
    }

    // MARK: - Helper computed props

    private var musclesWorked: Int {
        GamificationManager.muscleStatuses(workouts: workouts).filter { $0.state == .done || $0.state == .warning }.count
    }
    private var muscleProgress: Double { Double(musclesWorked) / 6.0 }

    // MARK: - Section label

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: "#6b6b80")).tracking(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Calendar

    private var workoutDayCounts: [Date: Int] {
        let cal = Calendar.current; var map: [Date: Int] = [:]
        for w in workouts { map[cal.startOfDay(for: w.date), default: 0] += 1 }
        return map
    }
    private func daysInMonth(_ d: Date) -> [Date] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: d),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: d)) else { return [] }
        return range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: first) }
    }
    private func firstWeekdayOffset(_ d: Date) -> Int {
        let cal = Calendar.current
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: d)) else { return 0 }
        return (cal.component(.weekday, from: first) + 5) % 7
    }

    var calendarSection: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    calendarMonth = Calendar.current.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth
                } label: { Image(systemName: "chevron.left").foregroundStyle(Color(hex: "#6b6b80")) }
                Spacer()
                Text(calendarMonth, format: .dateTime.month(.wide).year())
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Color(hex: "#f0f0f5"))
                Spacer()
                Button {
                    let n = Calendar.current.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth
                    if n <= Date() { calendarMonth = n }
                } label: { Image(systemName: "chevron.right").foregroundStyle(Color(hex: "#6b6b80")) }
                .disabled(Calendar.current.isDate(calendarMonth, equalTo: Date(), toGranularity: .month))
            }

            let days = ["Пн","Вт","Ср","Чт","Пт","Сб","Вс"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(days, id: \.self) { d in
                    Text(d).font(.system(size: 10)).foregroundStyle(Color(hex: "#6b6b80"))
                }
                ForEach(0..<firstWeekdayOffset(calendarMonth), id: \.self) { _ in
                    Color.clear.frame(height: 28)
                }
                ForEach(daysInMonth(calendarMonth), id: \.self) { date in
                    let cal = Calendar.current
                    let n = cal.component(.day, from: date)
                    let day = cal.startOfDay(for: date)
                    let c = workoutDayCounts[day] ?? 0
                    let today = cal.isDateInToday(date)
                    Button {
                        if let w = workoutsForDay(day).first { selectedDayWorkout = w }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(heatColor(c))
                            Text("\(n)").font(.system(size: 10)).foregroundStyle(c > 0 ? .black : Color(hex: "#f0f0f5"))
                        }
                        .frame(height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(today ? Color(hex: "#ff5c3a") : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(c == 0)
                }
            }
        }
        .padding(18)
        .darkCard()
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func workoutsForDay(_ day: Date) -> [Workout] {
        let cal = Calendar.current
        return workouts.filter { cal.startOfDay(for: $0.date) == day }
    }

    private func heatColor(_ c: Int) -> Color {
        switch c {
        case 0: return Color.white.opacity(0.06)
        case 1: return Color(hex: "#3aff9e").opacity(0.4)
        case 2: return Color(hex: "#3aff9e").opacity(0.65)
        default: return Color(hex: "#3aff9e").opacity(0.9)
        }
    }

    // MARK: - Summary cards

    var summaryCards: some View {
        let total = filtered.count
        let sets = filtered.flatMap { $0.workoutExercises }.flatMap { $0.workoutSets }.filter { $0.isCompleted }.count
        let vol  = filtered.flatMap { $0.workoutExercises }.flatMap { $0.workoutSets }.filter { $0.isCompleted }.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
        let first = filtered.first?.date
        let days  = first.map { max(1, Calendar.current.dateComponents([.day], from: $0, to: .now).day ?? 1) } ?? 1
        let avg   = Double(total) / max(1.0, Double(days) / 7.0)

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            miniStat("Тренировки", "\(total)", "figure.strengthtraining.traditional", Color(hex: "#5b8cff"))
            miniStat("Ср/нед", String(format: "%.1f", avg), "calendar", Color(hex: "#a855f7"))
            miniStat("Объём", formatVol(vol), "scalemass.fill", Color(hex: "#ff5c3a"))
            miniStat("Сетов", "\(sets)", "repeat", Color(hex: "#3aff9e"))
        }
        .padding(.horizontal, 16)
    }

    private func miniStat(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value).font(.system(size: 17, weight: .bold)).foregroundStyle(Color(hex: "#f0f0f5")).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.system(size: 11)).foregroundStyle(Color(hex: "#6b6b80"))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .darkCard()
    }

    // MARK: - Charts

    private var weeklyPoints: [WeekPoint] {
        let cal = Calendar.current; var map: [Date: (Int, Double)] = [:]
        for w in filtered {
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: w.date)
            let ws = cal.date(from: comps) ?? w.date
            let vol = w.workoutExercises.flatMap { $0.workoutSets }.filter { $0.isCompleted }.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
            map[ws] = ((map[ws]?.0 ?? 0) + 1, (map[ws]?.1 ?? 0) + vol)
        }
        return map.map { WeekPoint(weekStart: $0.key, count: $0.value.0, volume: $0.value.1) }
            .sorted { $0.weekStart < $1.weekStart }
    }

    private var bodyPartStats: [BodyPartStat] {
        var map: [String: Int] = [:]
        for w in filtered {
            for we in w.workoutExercises {
                let n = we.workoutSets.filter { $0.isCompleted }.count
                guard n > 0 else { continue }
                map[we.exercise.bodyPart, default: 0] += n
            }
        }
        return map.map { BodyPartStat(name: $0.key, sets: $0.value) }.sorted { $0.sets > $1.sets }
    }

    var activityChartView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Тренировки в неделю").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: "#f0f0f5"))
            Chart(weeklyPoints) { p in
                BarMark(x: .value("Неделя", p.weekStart, unit: .weekOfYear), y: .value("Кол-во", p.count))
                    .foregroundStyle(Color(hex: "#5b8cff").gradient).cornerRadius(4)
            }
            .frame(height: 160)
            .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear)) { AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true).foregroundStyle(Color(hex: "#6b6b80")) } }
        }
        .padding(18).darkCard().padding(.horizontal, 16)
    }

    var volumeChartView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Объём в неделю (кг)").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: "#f0f0f5"))
            Chart(weeklyPoints) { p in
                LineMark(x: .value("Неделя", p.weekStart, unit: .weekOfYear), y: .value("Объём", p.volume))
                    .foregroundStyle(Color(hex: "#ff5c3a")).interpolationMethod(.catmullRom)
                AreaMark(x: .value("Неделя", p.weekStart, unit: .weekOfYear), y: .value("Объём", p.volume))
                    .foregroundStyle(Color(hex: "#ff5c3a").opacity(0.12)).interpolationMethod(.catmullRom)
            }
            .frame(height: 160)
        }
        .padding(18).darkCard().padding(.horizontal, 16)
    }

    var bodyPartChartView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Сетов по группам мышц").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: "#f0f0f5"))
            Chart(bodyPartStats) { s in
                BarMark(x: .value("Сеты", s.sets), y: .value("Группа", s.name))
                    .foregroundStyle(bodyPartColor(s.name).gradient).cornerRadius(4)
                    .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                        Text("\(s.sets)").font(.caption2).foregroundStyle(Color(hex: "#6b6b80"))
                    }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(bodyPartStats.count) * 36)
        }
        .padding(18).darkCard().padding(.horizontal, 16)
    }

    private func bodyPartColor(_ name: String) -> Color {
        switch name {
        case BodyPart.chest.rawValue:     return Color(hex: "#5b8cff")
        case BodyPart.back.rawValue:      return Color(hex: "#3aff9e")
        case BodyPart.legs.rawValue:      return Color(hex: "#ff5c3a")
        case BodyPart.shoulders.rawValue: return Color(hex: "#ffb830")
        case BodyPart.arms.rawValue:      return Color(hex: "#a855f7")
        case BodyPart.abs.rawValue:       return Color(hex: "#f0f0f5")
        default: return Color(hex: "#6b6b80")
        }
    }
    private func formatVol(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1f т", v/1000) : String(format: "%.0f кг", v)
    }
}

// MARK: - PR Detail Sheet

struct PRDetailSheet: View {
    let detail: PRDetailInfo
    @Environment(\.dismiss) private var dismiss

    private var dateFmt: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM yyyy"
        return f
    }
    private var shortDateFmt: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "dd.MM"
        return f
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    bestWeightCard
                    bestVolumeCard
                    statsRow
                    if detail.weightHistory.count >= 2 { progressChart }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 40)
            }
            .background(Color(hex: "#0e0e12").ignoresSafeArea())
            .navigationTitle(detail.exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(Color(hex: "#4a8cff"))
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .toolbarBackground(Color(hex: "#0e0e12"), for: .navigationBar)
            .preferredColorScheme(.dark)
        }
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Text("🏆")
                .font(.system(size: 36))
                .frame(width: 60, height: 60)
                .background(Color(hex: "#ffb830").opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "#ffb830").opacity(0.3), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(detail.exerciseName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
                Text(detail.bodyPart)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#6b6b80"))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f", detail.bestWeight))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#ffb830"))
                Text("кг")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#6b6b80"))
            }
        }
        .padding(18)
        .darkCard(accentBorder: Color(hex: "#ffb830").opacity(0.25))
    }

    private var bestWeightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#ffb830"))
                Text("РЕКОРД ВЕСА")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .tracking(1)
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(String(format: "%.1f", detail.bestWeight)) кг × \(detail.bestWeightReps) повт.")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    Text(dateFmt.string(from: detail.bestWeightDate))
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#ffb830"))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Тренировка")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                    Text(detail.bestWeightWorkoutName.isEmpty ? "Без названия" : detail.bestWeightWorkoutName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .darkCard()
    }

    private var bestVolumeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#ff5c3a"))
                Text("РЕКОРД ОБЪЁМА")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .tracking(1)
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "%.0f кг", detail.bestVolume))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    Text("\(String(format: "%.1f", detail.bestVolumeWeight)) кг × \(detail.bestVolumeReps) повт.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                Spacer()
                Text(dateFmt.string(from: detail.bestVolumeDate))
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#ff5c3a"))
            }
        }
        .padding(16)
        .darkCard()
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statBox(value: "\(detail.totalWorkouts)", label: "тренировок", color: Color(hex: "#5b8cff"))
            statBox(value: "\(detail.totalSets)", label: "подходов", color: Color(hex: "#3aff9e"))
            statBox(
                value: daysSincePR,
                label: "дней назад",
                color: Color(hex: "#a855f7")
            )
        }
    }

    private var daysSincePR: String {
        let days = Calendar.current.dateComponents([.day], from: detail.bestWeightDate, to: Date()).day ?? 0
        return days == 0 ? "Сегодня" : "\(days)"
    }

    private func statBox(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .darkCard()
    }

    private var progressChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#5b8cff"))
                Text("ПРОГРЕСС ВЕСА")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .tracking(1)
            }

            Chart {
                ForEach(detail.weightHistory.indices, id: \.self) { i in
                    let point = detail.weightHistory[i]
                    LineMark(
                        x: .value("Дата", point.date),
                        y: .value("Вес", point.weight)
                    )
                    .foregroundStyle(Color(hex: "#ffb830"))
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Дата", point.date),
                        y: .value("Вес", point.weight)
                    )
                    .foregroundStyle(Color(hex: "#ffb830").opacity(0.1))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Дата", point.date),
                        y: .value("Вес", point.weight)
                    )
                    .foregroundStyle(Color(hex: "#ffb830"))
                    .symbolSize(point.weight == detail.bestWeight ? 50 : 20)
                }
            }
            .frame(height: 180)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel()
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
        }
        .padding(16)
        .darkCard()
    }
}

// MARK: - All PRs inline

struct AllPRsInlineView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var selectedPR: PRDetailInfo?

    private var grouped: [(String, [(Exercise, Double)])] {
        let list = exercises.compactMap { ex -> (Exercise, Double)? in
            guard ex.bodyPart != BodyPart.cardio.rawValue,
                  let best = PRManager.bestWeight(for: ex, in: context), best > 0 else { return nil }
            return (ex, best)
        }.sorted { $0.1 > $1.1 }
        return Dictionary(grouping: list, by: { $0.0.bodyPart })
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(spacing: 10) {
            if grouped.isEmpty {
                Text("Завершите сеты чтобы появились рекорды")
                    .font(.system(size: 14)).foregroundStyle(Color(hex: "#6b6b80"))
                    .padding(40)
            } else {
                ForEach(grouped, id: \.0) { bodyPart, items in
                    VStack(spacing: 0) {
                        HStack {
                            Text(bodyPart.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#6b6b80")).tracking(1)
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
                        ForEach(items, id: \.0.id) { (ex, weight) in
                            Button {
                                if let detail = PRManager.prDetail(for: ex, in: context) {
                                    selectedPR = detail
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "trophy.fill").font(.caption).foregroundStyle(Color(hex: "#ffb830"))
                                    Text(ex.name).font(.system(size: 14)).foregroundStyle(Color(hex: "#f0f0f5"))
                                    Spacer()
                                    Text(String(format: "%.1f кг", weight))
                                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color(hex: "#ffb830"))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color(hex: "#3a3a4a"))
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .overlay(Divider().padding(.leading, 16), alignment: .bottom)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .darkCard()
                    .padding(.horizontal, 16)
                }
            }
        }
        .sheet(item: $selectedPR) { detail in
            PRDetailSheet(detail: detail)
        }
    }
}
