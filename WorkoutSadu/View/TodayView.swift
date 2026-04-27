import SwiftUI
import SwiftData

struct TodayView: View {
    @Binding var selectedTab: Int
    @Environment(\.modelContext) private var context
    @State private var showDayReport = false
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @Query(filter: #Predicate<Habit> { !$0.archived }, sort: \Habit.createdAt) private var habits: [Habit]
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var allTodos: [TodoItem]
    @Query(sort: \FinanceTransaction.date, order: .reverse) private var transactions: [FinanceTransaction]
    @Query(sort: \FinanceAccount.createdAt) private var accounts: [FinanceAccount]
    @Query(sort: \WeeklyGoal.createdAt, order: .reverse) private var goals: [WeeklyGoal]
    @Query(sort: \NotificationEntry.date, order: .reverse) private var notificationEntries: [NotificationEntry]
    @Query private var profiles: [BodyProfile]
    @State private var showNotifications = false
    @State private var todaySteps: Int = 0

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Доброе утро"
        case 12..<18: return "Добрый день"
        case 18..<23: return "Добрый вечер"
        default:      return "Доброй ночи"
        }
    }

    private var dateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: Date()).capitalized
    }

    private var todayWorkouts: [Workout] {
        let cal = Calendar.current
        return workouts.filter { cal.isDateInToday($0.date) }
    }

    private var activeWorkout: Workout? {
        workouts.first { $0.finishedAt == nil }
    }

    private var pendingTodos: [TodoItem] {
        let cal = Calendar.current
        let today = Date()
        return allTodos.filter { todo in
            guard !todo.completed else { return false }
            guard let due = todo.dueDate else { return true }
            return cal.isDate(due, inSameDayAs: today)
        }
    }

    private var todayExpense: Int {
        let cal = Calendar.current
        return transactions
            .filter { cal.isDateInToday($0.date) && $0.type == .expense && $0.category != .transfers }
            .reduce(0) { $0 + $1.amount }
    }

    private var totalBalance: Int {
        let accountedBalance = accounts.reduce(0) { total, acc in
            let txs = transactions.filter { $0.accountID == acc.id }
            let inc = txs.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            let exp = txs.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
            return total + acc.balance + inc - exp
        }
        let unaccounted = transactions.filter { $0.accountID == nil }
        let uInc = unaccounted.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let uExp = unaccounted.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        return accountedBalance + uInc - uExp
    }

    private var habitsCompleted: Int { habits.filter { $0.isCompleted(on: Date()) }.count }

    private var currentWeekGoals: [WeeklyGoal] { goals.filter { $0.isCurrentWeek } }

    private var hasUnreadNotifications: Bool {
        let lastViewed = UserDefaults.standard.object(forKey: "NotificationHistory.lastViewed") as? Date ?? .distantPast
        let newest = notificationEntries.first?.date ?? .distantPast
        return newest > lastViewed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        headerCard
                        if todaySteps > 0 { stepsCard }
                        if activeWorkout != nil { activeWorkoutCard }
                        habitsCard
                        todosCard
                        financeCard
                        goalsCard
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("SADU")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showDayReport = true
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNotifications = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color(hex: "#f0f0f5"))
                            if hasUnreadNotifications {
                                Circle()
                                    .fill(Color(hex: "#ff5c3a"))
                                    .frame(width: 8, height: 8)
                                    .offset(x: 6, y: -4)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showNotifications) {
                NotificationHistoryView()
            }
            .onChange(of: showNotifications) { _, visible in
                if !visible {
                    UserDefaults.standard.set(Date(), forKey: "NotificationHistory.lastViewed")
                }
            }
            .sheet(isPresented: $showDayReport) {
                DayReportView(date: Date())
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await refreshSteps()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshSteps() }
        }
    }

    private func refreshSteps() async {
        guard profiles.first?.healthKitEnabled == true else { return }
        let steps = await HealthKitManager.shared.fetchSteps(for: Date())
        todaySteps = Int(steps)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 4) {
            Text(greeting)
                .font(.custom("BebasNeue-Regular", size: 32))
                .foregroundStyle(Color(hex: "#f0f0f5"))
            Text(dateString)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Steps

    private var stepsCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.system(size: 20))
                .foregroundStyle(Color(hex: "#3aff9e"))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("ШАГИ СЕГОДНЯ")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .tracking(1)
                Text("\(todaySteps)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
            }
            Spacer()
            
            // Индикатор цели (например 10к)
            let progress = min(1.0, Double(todaySteps) / 10000.0)
            ZStack {
                Circle()
                    .stroke(Color(hex: "#1a1a24"), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color(hex: "#3aff9e"), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 36, height: 36)
        }
        .padding(14)
        .darkCard()
    }

    // MARK: - Active workout

    private var activeWorkoutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(Color(hex: "#ff5c3a"))
                Text("ТРЕНИРОВКА В ПРОЦЕССЕ")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "#ff5c3a"))
                    .tracking(1)
            }
            if let w = activeWorkout {
                Text(w.name.isEmpty ? "Тренировка" : w.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
                Text("\(w.workoutExercises.count) упражнений")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#6b6b80"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .darkCard(accentBorder: Color(hex: "#ff5c3a").opacity(0.3))
    }

    // MARK: - Habits

    private var habitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "repeat").foregroundStyle(Color(hex: "#3aff9e"))
                Text("ПРИВЫЧКИ")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .tracking(1)
                Spacer()
                Text("\(habitsCompleted)/\(habits.count)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(habitsCompleted == habits.count && !habits.isEmpty ? Color(hex: "#3aff9e") : Color(hex: "#f0f0f5"))
            }

            if habits.isEmpty {
                Text("Добавьте привычки в разделе Задачи")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#6b6b80"))
            } else {
                ForEach(habits) { habit in
                    let done = habit.isCompleted(on: Date())
                    HStack(spacing: 10) {
                        Button {
                            if done {
                                if let entry = habit.entries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: Date()) }) {
                                    context.delete(entry)
                                }
                            } else {
                                let entry = HabitEntry(date: Date(), habit: habit)
                                context.insert(entry)
                            }
                            try? context.save()
                        } label: {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(done ? Color(hex: habit.colorHex) : Color(hex: "#6b6b80"))
                        }
                        .buttonStyle(.plain)

                        Text(habit.name)
                            .font(.system(size: 14))
                            .foregroundStyle(done ? Color(hex: "#6b6b80") : Color(hex: "#f0f0f5"))
                            .strikethrough(done)

                        Spacer()

                        let streak = habit.streak()
                        if streak > 0 {
                            Text("\(streak) дн")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(hex: "#ffb830"))
                        }
                    }
                }
            }
        }
        .padding(14)
        .darkCard()
        .contentShape(Rectangle())
        .onTapGesture { selectedTab = 2 }
    }

    // MARK: - Todos

    private var todosCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checklist").foregroundStyle(Color(hex: "#5b8cff"))
                Text("ЗАДАЧИ")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .tracking(1)
                Spacer()
                if !pendingTodos.isEmpty {
                    Text("\(pendingTodos.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color(hex: "#5b8cff"))
                        .clipShape(Capsule())
                }
            }

            if pendingTodos.isEmpty {
                Text("Все задачи выполнены")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#6b6b80"))
            } else {
                ForEach(pendingTodos.prefix(5)) { todo in
                    HStack(spacing: 10) {
                        Button {
                            todo.completed = true
                            try? context.save()
                        } label: {
                            Image(systemName: "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                        }
                        .buttonStyle(.plain)

                        Text(todo.title)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "#f0f0f5"))
                            .lineLimit(1)
                    }
                }
                if pendingTodos.count > 5 {
                    Text("+ ещё \(pendingTodos.count - 5)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
        }
        .padding(14)
        .darkCard()
        .contentShape(Rectangle())
        .onTapGesture { selectedTab = 2 }
    }

    // MARK: - Finance

    private var financeCard: some View {
        HStack(spacing: 10) {
            VStack(spacing: 4) {
                Image(systemName: "banknote.fill").foregroundStyle(Color(hex: "#3aff9e"))
                Text("Баланс")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                Text(formatAmount(totalBalance))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(totalBalance >= 0 ? Color(hex: "#3aff9e") : Color(hex: "#ff5c3a"))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .darkCard()

            VStack(spacing: 4) {
                Image(systemName: "arrow.up.circle.fill").foregroundStyle(Color(hex: "#ff5c3a"))
                Text("Сегодня")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                Text(todayExpense > 0 ? "-\(formatAmount(todayExpense))" : "0")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(todayExpense > 0 ? Color(hex: "#ff5c3a") : Color(hex: "#6b6b80"))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .darkCard()
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedTab = 3 }
    }

    // MARK: - Goals

    private var goalsCard: some View {
        Group {
            if !currentWeekGoals.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "target").foregroundStyle(Color(hex: "#ffb830"))
                        Text("ЦЕЛИ НЕДЕЛИ")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                            .tracking(1)
                    }

                    ForEach(currentWeekGoals) { goal in
                        HStack {
                            Text(goal.title)
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "#f0f0f5"))
                            Spacer()
                            Text("\(goal.currentCount)/\(goal.targetCount)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(goal.progress >= 1 ? Color(hex: "#3aff9e") : Color(hex: "#f0f0f5"))
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(hex: "#1a1a24"))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(goal.progress >= 1 ? Color(hex: "#3aff9e") : Color(hex: "#ff5c3a"))
                                    .frame(width: geo.size.width * goal.progress, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .padding(14)
                .darkCard()
                .contentShape(Rectangle())
                .onTapGesture { selectedTab = 4 }
            }
        }
    }

    // MARK: - Helpers

    private func formatAmount(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        let absStr = f.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        return value < 0 ? "-\(absStr)" : absStr
    }
}
