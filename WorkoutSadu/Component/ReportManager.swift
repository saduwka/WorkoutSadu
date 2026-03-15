import Foundation
import SwiftData
import UserNotifications
import FirebaseAI

// MARK: - Day snapshot (данные за день для отчёта)

/// Один приём пищи для отчёта (название, тип, время, калории).
struct DayReportMealEntry: Equatable {
    var mealType: String
    var timeString: String
    var name: String
    var calories: Int
}

struct DayReportSnapshot: Equatable {
    var workoutSummary: String
    var caloriesEaten: Int
    var caloriesBurned: Int
    var calorieTarget: Int?
    var waterML: Int
    var mealsDetail: [DayReportMealEntry]
    var expense: Int
    var income: Int
    var expenseCategories: [(category: String, amount: Int)]
    var habitsDone: Int
    var habitsTotal: Int
    var habitsList: [(name: String, done: Bool, streak: Int)]
    var todosDone: Int
    var todosPending: Int
    var todoTitles: [String]
    var goalsList: [(title: String, current: Int, target: Int)]
    var moodRating: Int?
    var moodNote: String

    var textSummary: String {
        var lines: [String] = []
        if !workoutSummary.isEmpty { lines.append("Тренировка: \(workoutSummary)") }
        lines.append("Калории: съедено \(caloriesEaten), сожжено \(caloriesBurned)" + (calorieTarget.map { ", норма \($0)" } ?? ""))
        if !mealsDetail.isEmpty {
            lines.append("Еда по приёмам: " + mealsDetail.map { "\($0.mealType) \($0.timeString) — \($0.name) \($0.calories) ккал" }.joined(separator: "; "))
        }
        if waterML > 0 { lines.append("Вода: \(waterML) мл") }
        if expense > 0 || income > 0 {
            lines.append("Деньги: расход −\(expense), доход +\(income)" + (expenseCategories.isEmpty ? "" : ". Категории расходов: " + expenseCategories.prefix(5).map { "\($0.category) \($0.amount)" }.joined(separator: ", ")))
        }
        if habitsTotal > 0 { lines.append("Привычки: \(habitsDone)/\(habitsTotal)") }
        if !habitsList.isEmpty {
            lines.append(habitsList.map { "\($0.name) \($0.done ? "✓" : "—") стрик \($0.streak)" }.joined(separator: ", "))
        }
        if todosDone > 0 || todosPending > 0 { lines.append("Задачи: выполнено \(todosDone), в ожидании \(todosPending)") }
        if !todoTitles.isEmpty { lines.append("Не сделано: \(todoTitles.prefix(5).joined(separator: ", "))") }
        if !goalsList.isEmpty {
            lines.append("Цели: \(goalsList.map { "\($0.title) \($0.current)/\($0.target)" }.joined(separator: ", "))")
        }
        if let r = moodRating { lines.append("Настроение: \(r)/5") }
        if !moodNote.isEmpty { lines.append("Заметка: \(moodNote)") }
        return lines.joined(separator: "\n")
    }

    static func == (lhs: DayReportSnapshot, rhs: DayReportSnapshot) -> Bool {
        lhs.workoutSummary == rhs.workoutSummary && lhs.caloriesEaten == rhs.caloriesEaten
            && lhs.caloriesBurned == rhs.caloriesBurned && lhs.calorieTarget == rhs.calorieTarget
            && lhs.waterML == rhs.waterML && lhs.mealsDetail == rhs.mealsDetail
            && lhs.expense == rhs.expense && lhs.income == rhs.income
            && lhs.expenseCategories.elementsEqual(rhs.expenseCategories) { $0.category == $1.category && $0.amount == $1.amount }
            && lhs.habitsDone == rhs.habitsDone && lhs.habitsTotal == rhs.habitsTotal
            && lhs.habitsList.elementsEqual(rhs.habitsList) { $0.name == $1.name && $0.done == $1.done && $0.streak == $1.streak }
            && lhs.todosDone == rhs.todosDone && lhs.todosPending == rhs.todosPending && lhs.todoTitles == rhs.todoTitles
            && lhs.goalsList.elementsEqual(rhs.goalsList) { $0.title == $1.title && $0.current == $1.current && $0.target == $1.target }
            && lhs.moodRating == rhs.moodRating && lhs.moodNote == rhs.moodNote
    }
}

// MARK: - Range snapshot (произвольный период от–до)

struct RangeReportSnapshot {
    var from: Date
    var to: Date
    var daysCount: Int
    var workoutsCount: Int
    var workoutNames: [String]
    var totalExpense: Int
    var totalIncome: Int
    var topExpensesByCategory: [(category: String, amount: Int)]
    var habitsSummary: [RangeHabitSummary]

    var textSummary: String {
        var lines: [String] = []
        lines.append("Период: \(daysCount) дн.")
        lines.append("Тренировки: \(workoutsCount) — \(workoutNames.prefix(5).joined(separator: ", "))")
        lines.append("Расход: \(totalExpense), доход: \(totalIncome)")
        if !topExpensesByCategory.isEmpty {
            lines.append("Топ расходов: \(topExpensesByCategory.prefix(5).map { "\($0.category) \($0.amount)" }.joined(separator: ", "))")
        }
        if !habitsSummary.isEmpty {
            lines.append("Привычки: \(habitsSummary.map { "\($0.name) \($0.daysDone)/\($0.totalDays)" }.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }
}

struct RangeHabitSummary {
    var name: String
    var daysDone: Int
    var totalDays: Int
}

// MARK: - Week snapshot

struct WeekReportSnapshot: Equatable {
    var weekStart: Date
    var workoutsCount: Int
    var workoutNames: [String]
    var weightEntries: [(date: Date, weight: Double)]
    var topExpensesByCategory: [(category: String, amount: Int)]
    var totalExpense: Int
    var totalIncome: Int
    var habitsKept: [(name: String, streak: Int)]
    var habitsBroke: [String]
    var goalsList: [(title: String, current: Int, target: Int)]

    var textSummary: String {
        var lines: [String] = []
        lines.append("Тренировки: \(workoutsCount) — \(workoutNames.prefix(5).joined(separator: ", "))")
        if !weightEntries.isEmpty {
            let w = weightEntries.sorted { $0.date < $1.date }
            if let first = w.first, let last = w.last {
                lines.append("Вес: с \(Int(first.weight)) по \(Int(last.weight)) кг")
            }
        }
        lines.append("Расходы за неделю: \(totalExpense), доходы: \(totalIncome)")
        if !topExpensesByCategory.isEmpty {
            lines.append("Топ расходов: \(topExpensesByCategory.prefix(5).map { "\($0.category) \($0.amount)" }.joined(separator: ", "))")
        }
        if !habitsKept.isEmpty { lines.append("Привычки держали: \(habitsKept.map { "\($0.name) (\($0.streak) дн.)" }.joined(separator: ", "))") }
        if !habitsBroke.isEmpty { lines.append("Привычки сломали: \(habitsBroke.joined(separator: ", "))") }
        if !goalsList.isEmpty { lines.append("Цели: \(goalsList.map { "\($0.title) \($0.current)/\($0.target)" }.joined(separator: ", "))") }
        return lines.joined(separator: "\n")
    }

    static func == (lhs: WeekReportSnapshot, rhs: WeekReportSnapshot) -> Bool {
        lhs.weekStart == rhs.weekStart && lhs.workoutsCount == rhs.workoutsCount
            && lhs.workoutNames == rhs.workoutNames
            && lhs.weightEntries.elementsEqual(rhs.weightEntries) { $0.date == $1.date && $0.weight == $1.weight }
            && lhs.topExpensesByCategory.elementsEqual(rhs.topExpensesByCategory) { $0.category == $1.category && $0.amount == $1.amount }
            && lhs.totalExpense == rhs.totalExpense && lhs.totalIncome == rhs.totalIncome
            && lhs.habitsKept.elementsEqual(rhs.habitsKept) { $0.name == $1.name && $0.streak == $1.streak }
            && lhs.habitsBroke == rhs.habitsBroke
            && lhs.goalsList.elementsEqual(rhs.goalsList) { $0.title == $1.title && $0.current == $1.current && $0.target == $1.target }
    }
}

// MARK: - Month snapshot

struct MonthReportSnapshot: Equatable {
    var monthStart: Date
    var workoutsCount: Int
    var workoutsPrevMonth: Int
    var totalExpense: Int
    var totalIncome: Int
    var expensePrevMonth: Int
    var incomePrevMonth: Int
    var topExpensesByCategory: [(category: String, amount: Int)]
    var bestHabitStreak: (name: String, streak: Int)?
    var goalsCompleted: [String]

    static func == (lhs: MonthReportSnapshot, rhs: MonthReportSnapshot) -> Bool {
        lhs.monthStart == rhs.monthStart
            && lhs.workoutsCount == rhs.workoutsCount
            && lhs.workoutsPrevMonth == rhs.workoutsPrevMonth
            && lhs.totalExpense == rhs.totalExpense
            && lhs.totalIncome == rhs.totalIncome
            && lhs.expensePrevMonth == rhs.expensePrevMonth
            && lhs.incomePrevMonth == rhs.incomePrevMonth
            && lhs.topExpensesByCategory.elementsEqual(rhs.topExpensesByCategory) { $0.category == $1.category && $0.amount == $1.amount }
            && lhs.goalsCompleted == rhs.goalsCompleted
            && lhs.bestHabitStreak?.name == rhs.bestHabitStreak?.name
            && lhs.bestHabitStreak?.streak == rhs.bestHabitStreak?.streak
    }

    var textSummary: String {
        var lines: [String] = []
        lines.append("Тренировки: \(workoutsCount) (в прошлом месяце \(workoutsPrevMonth))")
        lines.append("Баланс: доход +\(totalIncome), расход −\(totalExpense) (прошлый месяц: +\(incomePrevMonth)/−\(expensePrevMonth))")
        if !topExpensesByCategory.isEmpty {
            lines.append("Топ расходов: \(topExpensesByCategory.prefix(5).map { "\($0.category) \($0.amount)" }.joined(separator: ", "))")
        }
        if let best = bestHabitStreak { lines.append("Лучший стрик: \(best.name) — \(best.streak) дн.") }
        if !goalsCompleted.isEmpty { lines.append("Цели выполнены: \(goalsCompleted.joined(separator: ", "))") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Report Manager

final class ReportManager {

    static let shared = ReportManager()

    private static let dailyReportID = "sadu-report-daily"
    private static let weeklyReportID = "sadu-report-weekly"
    private static let monthlyReportID = "sadu-report-monthly"

    private init() {}

    // MARK: - Сбор данных за день

    func collectDaySnapshot(context: ModelContext, date: Date) -> DayReportSnapshot {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)

        var workoutSummary = ""
        var caloriesEaten = 0
        var caloriesBurned = 0
        var calorieTarget: Int?
        var expense = 0
        var income = 0
        var habitsDone = 0
        var habitsTotal = 0
        var habitsList: [(name: String, done: Bool, streak: Int)] = []
        var todosDone = 0
        var todosPending = 0
        var todoTitles: [String] = []
        var goalsList: [(title: String, current: Int, target: Int)] = []
        var moodRating: Int?
        var moodNote = ""
        var waterML = 0
        var mealsDetail: [DayReportMealEntry] = []
        var expenseCategories: [(category: String, amount: Int)] = []
        if let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) {
            let waterDesc = FetchDescriptor<WaterEntry>(
                predicate: #Predicate<WaterEntry> { $0.date >= dayStart && $0.date < dayEnd }
            )
            let waterEntries = (try? context.fetch(waterDesc)) ?? []
            waterML = waterEntries.reduce(0) { $0 + $1.amountML }
        }

        if let workouts = try? context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.date)])) {
            let dayWorkouts = workouts.filter { $0.finishedAt != nil && cal.isDate($0.date, inSameDayAs: date) }
            if !dayWorkouts.isEmpty {
                workoutSummary = "\(dayWorkouts.count) трен., \(dayWorkouts.flatMap { $0.workoutExercises.map { $0.exercise.name } }.joined(separator: ", "))"
            }
            let profile = try? context.fetch(FetchDescriptor<BodyProfile>()).first
            caloriesBurned = CalorieCalculator.burnedOnDay(date, workouts: workouts, profile: profile)
            calorieTarget = CalorieCalculator.dailyTarget(profile: profile)
        }

        let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f
        }()
        if let meals = try? context.fetch(FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.date)])) {
            let dayMeals = meals.filter { cal.isDate($0.date, inSameDayAs: date) }
            caloriesEaten = dayMeals.reduce(0) { $0 + $1.calories }
            mealsDetail = dayMeals
                .sorted { $0.date < $1.date }
                .map { DayReportMealEntry(mealType: $0.mealType.rawValue, timeString: timeFormatter.string(from: $0.date), name: $0.name, calories: $0.calories) }
        }

        if let transactions = try? context.fetch(FetchDescriptor<FinanceTransaction>()) {
            let dayTx = transactions.filter { cal.isDate($0.date, inSameDayAs: date) && $0.category != .transfers }
            expense = dayTx.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
            income = dayTx.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            var byCat: [String: Int] = [:]
            for tx in dayTx where tx.type == .expense {
                byCat[tx.category.rawValue, default: 0] += tx.amount
            }
            expenseCategories = byCat.sorted { $0.value > $1.value }.map { (category: $0.key, amount: $0.value) }
        }

        if let habits = try? context.fetch(FetchDescriptor<Habit>(predicate: #Predicate<Habit> { !$0.archived }, sortBy: [SortDescriptor(\.createdAt)])) {
            habitsTotal = habits.count
            habitsDone = habits.filter { $0.isCompleted(on: date) }.count
            habitsList = habits.map { (name: $0.name, done: $0.isCompleted(on: date), streak: $0.streak()) }
        }

        if let todos = try? context.fetch(FetchDescriptor<TodoItem>()) {
            let dayTodos = todos.filter { t in
                guard let due = t.dueDate else { return false }
                return cal.isDate(due, inSameDayAs: date)
            }
            todosDone = dayTodos.filter { $0.completed }.count
            todosPending = dayTodos.filter { !$0.completed }.count
            todoTitles = dayTodos.filter { !$0.completed }.map(\.title)
        }

        if let goals = try? context.fetch(FetchDescriptor<WeeklyGoal>()) {
            goalsList = goals.filter { $0.isCurrentPeriod }.map { (title: $0.title, current: $0.currentCount, target: $0.targetCount) }
        }

        if let allMoods = try? context.fetch(FetchDescriptor<MoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])),
           let m = allMoods.first(where: { cal.isDate($0.date, inSameDayAs: date) }) {
            moodRating = m.rating
            moodNote = m.note
        }

        return DayReportSnapshot(
            workoutSummary: workoutSummary,
            caloriesEaten: caloriesEaten,
            caloriesBurned: caloriesBurned,
            calorieTarget: calorieTarget,
            waterML: waterML,
            mealsDetail: mealsDetail,
            expense: expense,
            income: income,
            expenseCategories: expenseCategories,
            habitsDone: habitsDone,
            habitsTotal: habitsTotal,
            habitsList: habitsList,
            todosDone: todosDone,
            todosPending: todosPending,
            todoTitles: todoTitles,
            goalsList: goalsList,
            moodRating: moodRating,
            moodNote: moodNote
        )
    }

    // MARK: - Промпт для LifeBro (дневной отчёт)

    func buildDayReportPrompt(snapshot: DayReportSnapshot, date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "d MMMM"
        let dateStr = df.string(from: date)
        return """
        Сводка за \(dateStr):
        \(snapshot.textSummary)

        Дай полноценный комментарий к дню в стиле Life Bro (дружеский, мотивирующий). ОБЯЗАТЕЛЬНО включи:
        1) По еде: что человек ел и во сколько (по данным из сводки), плюс один короткий совет по питанию на следующий день.
        2) По финансам: если в сводке есть расходы/доходы — кратко отметь, как день с точки зрения денег (уложился ли в план, на что ушло больше всего).
        3) Общий итог дня: что получилось, что можно улучшить.
        Пиши одним связным текстом, 4–7 предложений, без списков и markdown. Русский язык.
        """
    }

    // MARK: - Сбор данных за период (от–до)

    func collectRangeSnapshot(context: ModelContext, from: Date, to: Date) -> RangeReportSnapshot {
        let cal = Calendar.current
        let fromStart = cal.startOfDay(for: from)
        let toEnd = cal.startOfDay(for: to)
        let daysCount = max(1, (cal.dateComponents([.day], from: fromStart, to: toEnd).day ?? 0) + 1)

        var workoutsCount = 0
        var workoutNames: [String] = []
        var totalExpense = 0
        var totalIncome = 0
        var expensesByCategory: [String: Int] = [:]
        var habitsSummary: [RangeHabitSummary] = []

        if let workouts = try? context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.date)])) {
            let inRange = workouts.filter { $0.finishedAt != nil && $0.date >= fromStart && $0.date <= toEnd }
            workoutsCount = inRange.count
            workoutNames = inRange.map { $0.name.isEmpty ? "Тренировка" : $0.name }
        }

        if let transactions = try? context.fetch(FetchDescriptor<FinanceTransaction>()) {
            let rangeTx = transactions.filter { $0.date >= fromStart && $0.date <= toEnd && $0.category != .transfers }
            totalExpense = rangeTx.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
            totalIncome = rangeTx.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            for tx in rangeTx where tx.type == .expense {
                expensesByCategory[tx.category.rawValue, default: 0] += tx.amount
            }
        }
        let topExpensesByCategory = expensesByCategory.sorted { $0.value > $1.value }.map { (category: $0.key, amount: $0.value) }

        if let habits = try? context.fetch(FetchDescriptor<Habit>(predicate: #Predicate<Habit> { !$0.archived }, sortBy: [SortDescriptor(\.createdAt)])) {
            var day = fromStart
            while day <= toEnd {
                for h in habits {
                    if let idx = habitsSummary.firstIndex(where: { $0.name == h.name }) {
                        habitsSummary[idx].totalDays += 1
                        if h.isCompleted(on: day) { habitsSummary[idx].daysDone += 1 }
                    } else {
                        habitsSummary.append(RangeHabitSummary(name: h.name, daysDone: h.isCompleted(on: day) ? 1 : 0, totalDays: 1))
                    }
                }
                day = cal.date(byAdding: .day, value: 1, to: day) ?? day
            }
        }

        return RangeReportSnapshot(
            from: fromStart,
            to: toEnd,
            daysCount: daysCount,
            workoutsCount: workoutsCount,
            workoutNames: workoutNames,
            totalExpense: totalExpense,
            totalIncome: totalIncome,
            topExpensesByCategory: topExpensesByCategory,
            habitsSummary: habitsSummary
        )
    }

    func buildRangeReportPrompt(snapshot: RangeReportSnapshot) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "d MMM"
        let fromStr = df.string(from: snapshot.from)
        let toStr = df.string(from: snapshot.to)
        return """
        Отчёт за период \(fromStr) – \(toStr) (\(snapshot.daysCount) дн.):
        \(snapshot.textSummary)

        Дай ОДИН короткий абзац (2–4 предложения) — комментарий к периоду в стиле Life Bro: мотивирующий, подведи итог. Без списков и markdown. Русский язык.
        """
    }

    // MARK: - Сбор данных за неделю

    func collectWeekSnapshot(context: ModelContext, dateInWeek: Date) -> WeekReportSnapshot {
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: dateInWeek)
        guard let weekStart = cal.date(from: comps) else { return emptyWeekSnapshot(dateInWeek) }
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return emptyWeekSnapshot(dateInWeek) }

        var workoutsCount = 0
        var workoutNames: [String] = []
        var weightEntries: [(date: Date, weight: Double)] = []
        var expensesByCategory: [String: Int] = [:]
        var totalExpense = 0
        var totalIncome = 0
        var habitsKept: [(name: String, streak: Int)] = []
        var habitsBroke: [String] = []
        var goalsList: [(title: String, current: Int, target: Int)] = []

        if let workouts = try? context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.date)])) {
            let inWeek = workouts.filter { $0.finishedAt != nil && $0.date >= weekStart && $0.date < weekEnd }
            workoutsCount = inWeek.count
            workoutNames = inWeek.map { $0.name.isEmpty ? "Тренировка" : $0.name }
        }

        if let weights = try? context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)])) {
            weightEntries = weights.filter { $0.date >= weekStart && $0.date < weekEnd }.map { ($0.date, $0.weight) }
        }

        if let transactions = try? context.fetch(FetchDescriptor<FinanceTransaction>()) {
            let weekTx = transactions.filter { $0.date >= weekStart && $0.date < weekEnd && $0.category != .transfers }
            totalExpense = weekTx.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
            totalIncome = weekTx.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            for tx in weekTx where tx.type == .expense {
                expensesByCategory[tx.category.rawValue, default: 0] += tx.amount
            }
        }
        let topExpensesByCategory = expensesByCategory.sorted { $0.value > $1.value }.map { (category: $0.key, amount: $0.value) }

        if let habits = try? context.fetch(FetchDescriptor<Habit>(predicate: #Predicate<Habit> { !$0.archived }, sortBy: [SortDescriptor(\.createdAt)])) {
            for h in habits {
                let streak = h.streak()
                var completedAllDays = true
                var completedSomeDays = false
                var day = weekStart
                while day < weekEnd {
                    let done = h.isCompleted(on: day)
                    if done { completedSomeDays = true }
                    else { completedAllDays = false }
                    day = cal.date(byAdding: .day, value: 1, to: day) ?? day
                }
                if completedAllDays && streak >= 7 { habitsKept.append((h.name, streak)) }
                else if completedSomeDays && !completedAllDays { habitsBroke.append(h.name) }
            }
        }

        if let goals = try? context.fetch(FetchDescriptor<WeeklyGoal>()) {
            goalsList = goals.filter { g in
                cal.isDate(g.weekStart, inSameDayAs: weekStart) || (g.weekStart >= weekStart && g.weekStart < weekEnd)
            }.map { (title: $0.title, current: $0.currentCount, target: $0.targetCount) }
        }

        return WeekReportSnapshot(
            weekStart: weekStart,
            workoutsCount: workoutsCount,
            workoutNames: workoutNames,
            weightEntries: weightEntries,
            topExpensesByCategory: topExpensesByCategory,
            totalExpense: totalExpense,
            totalIncome: totalIncome,
            habitsKept: habitsKept,
            habitsBroke: habitsBroke,
            goalsList: goalsList
        )
    }

    private func emptyWeekSnapshot(_ date: Date) -> WeekReportSnapshot {
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let weekStart = cal.date(from: comps) ?? date
        return WeekReportSnapshot(weekStart: weekStart, workoutsCount: 0, workoutNames: [], weightEntries: [], topExpensesByCategory: [], totalExpense: 0, totalIncome: 0, habitsKept: [], habitsBroke: [], goalsList: [])
    }

    // MARK: - Сбор данных за месяц

    func collectMonthSnapshot(context: ModelContext, dateInMonth: Date) -> MonthReportSnapshot {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: dateInMonth)
        guard let monthStart = cal.date(from: comps) else { return emptyMonthSnapshot(dateInMonth) }
        guard let nextMonth = cal.date(byAdding: .month, value: 1, to: monthStart),
              let prevMonthStart = cal.date(byAdding: .month, value: -1, to: monthStart) else { return emptyMonthSnapshot(dateInMonth) }

        var workoutsCount = 0
        var workoutsPrevMonth = 0
        var totalExpense = 0
        var totalIncome = 0
        var expensePrevMonth = 0
        var incomePrevMonth = 0
        var expensesByCategory: [String: Int] = [:]
        var bestHabitStreak: (name: String, streak: Int)?
        var goalsCompleted: [String] = []

        if let workouts = try? context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.date)])) {
            workoutsCount = workouts.filter { $0.finishedAt != nil && $0.date >= monthStart && $0.date < nextMonth }.count
            let prevMonthEnd = monthStart
            workoutsPrevMonth = workouts.filter { $0.finishedAt != nil && $0.date >= prevMonthStart && $0.date < prevMonthEnd }.count
        }

        if let transactions = try? context.fetch(FetchDescriptor<FinanceTransaction>()) {
            let monthTx = transactions.filter { $0.date >= monthStart && $0.date < nextMonth && $0.category != .transfers }
            totalExpense = monthTx.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
            totalIncome = monthTx.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            for tx in monthTx where tx.type == .expense {
                expensesByCategory[tx.category.rawValue, default: 0] += tx.amount
            }
            let prevTx = transactions.filter { $0.date >= prevMonthStart && $0.date < monthStart && $0.category != .transfers }
            expensePrevMonth = prevTx.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
            incomePrevMonth = prevTx.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        }
        let topExpensesByCategory = expensesByCategory.sorted { $0.value > $1.value }.map { (category: $0.key, amount: $0.value) }

        if let habits = try? context.fetch(FetchDescriptor<Habit>(predicate: #Predicate<Habit> { !$0.archived })) {
            for h in habits {
                let s = h.streak()
                if let cur = bestHabitStreak { if s > cur.streak { bestHabitStreak = (h.name, s) } }
                else if s > 0 { bestHabitStreak = (h.name, s) }
            }
        }

        if let goals = try? context.fetch(FetchDescriptor<WeeklyGoal>()) {
            goalsCompleted = goals.filter { $0.isCurrentPeriod && $0.currentCount >= $0.targetCount }.map(\.title)
        }

        return MonthReportSnapshot(
            monthStart: monthStart,
            workoutsCount: workoutsCount,
            workoutsPrevMonth: workoutsPrevMonth,
            totalExpense: totalExpense,
            totalIncome: totalIncome,
            expensePrevMonth: expensePrevMonth,
            incomePrevMonth: incomePrevMonth,
            topExpensesByCategory: topExpensesByCategory,
            bestHabitStreak: bestHabitStreak,
            goalsCompleted: goalsCompleted
        )
    }

    private func emptyMonthSnapshot(_ date: Date) -> MonthReportSnapshot {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        let monthStart = cal.date(from: comps) ?? date
        return MonthReportSnapshot(monthStart: monthStart, workoutsCount: 0, workoutsPrevMonth: 0, totalExpense: 0, totalIncome: 0, expensePrevMonth: 0, incomePrevMonth: 0, topExpensesByCategory: [], bestHabitStreak: nil, goalsCompleted: [])
    }

    // MARK: - Промпты для недели и месяца

    func buildWeekReportPrompt(snapshot: WeekReportSnapshot) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "d MMM"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: snapshot.weekStart) ?? snapshot.weekStart
        let rangeStr = "\(df.string(from: snapshot.weekStart)) – \(df.string(from: end))"
        return """
        Недельный отчёт (\(rangeStr)):
        \(snapshot.textSummary)

        Дай комментарий к неделе в стиле Life Bro: подведи итог тренировкам и привычкам, отметь прогресс. ОБЯЗАТЕЛЬНО включи краткий блок по финансам: как неделя с точки зрения расходов и доходов, на что ушло больше всего. 4–6 предложений, без списков и markdown. Русский язык.
        """
    }

    func buildMonthReportPrompt(snapshot: MonthReportSnapshot) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "LLLL yyyy"
        let monthStr = df.string(from: snapshot.monthStart)
        return """
        Месячный отчёт (\(monthStr)):
        \(snapshot.textSummary)

        Дай комментарий к месяцу в стиле Life Bro: подведи итоги, сравни с прошлым месяцем, отметь достижения. ОБЯЗАТЕЛЬНО включи краткий блок по финансам: как месяц по доходам и расходам, сравнение с прошлым месяцем, главные статьи расходов. 4–6 предложений, без списков и markdown. Русский язык.
        """
    }

    // MARK: - Генерация AI-комментария (стриминг)

    func generateReportCommentStream(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let ai = FirebaseAI.firebaseAI(backend: .googleAI())
                    let model = ai.generativeModel(
                        modelName: "gemini-2.5-flash-lite",
                        generationConfig: GenerationConfig(temperature: 0.7, maxOutputTokens: 512)
                    )
                    let chat = model.startChat(history: [])
                    let stream = try chat.sendMessageStream(prompt)
                    for try await chunk in stream {
                        if let text = chunk.text {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Синхронная генерация (для push или сохранения).
    func generateReportComment(prompt: String) async throws -> String {
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let model = ai.generativeModel(
            modelName: "gemini-2.5-flash-lite",
            generationConfig: GenerationConfig(temperature: 0.7, maxOutputTokens: 512)
        )
        let response = try await model.generateContent(prompt)
        return response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Push-уведомления (планировщик)

    func scheduleAllReportNotifications() {
        scheduleDailyReport()
        scheduleWeeklyReport()
        scheduleMonthlyReport()
    }

    func scheduleDailyReport() {
        let content = UNMutableNotificationContent()
        content.title = "SADU — Итоги дня"
        content.body = "Посмотри сводку и комментарий Life Bro"
        content.sound = .default
        content.userInfo = ["type": "dayReport"]

        var dateComponents = DateComponents()
        dateComponents.hour = 21
        dateComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: Self.dailyReportID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    func scheduleWeeklyReport() {
        let content = UNMutableNotificationContent()
        content.title = "SADU — Недельный отчёт"
        content.body = "Итоги недели от Life Bro"
        content.sound = .default
        content.userInfo = ["type": "weekReport"]

        var dateComponents = DateComponents()
        dateComponents.weekday = 1
        dateComponents.hour = 20
        dateComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: Self.weeklyReportID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    func scheduleMonthlyReport() {
        let content = UNMutableNotificationContent()
        content.title = "SADU — Месячный отчёт"
        content.body = "Итоги прошлого месяца от Life Bro"
        content.sound = .default
        content.userInfo = ["type": "monthReport"]

        var dateComponents = DateComponents()
        dateComponents.day = 1
        dateComponents.hour = 9
        dateComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: Self.monthlyReportID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
