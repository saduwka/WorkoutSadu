import SwiftData
import Foundation

@Model
final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "checkmark.circle"
    var colorHex: String = "#ff5c3a"
    var createdAt: Date = Date()
    var archived: Bool = false

    @Relationship(deleteRule: .cascade) var entries: [HabitEntry] = []
    @Relationship(deleteRule: .cascade) var linkedTodos: [TodoItem] = []

    init(name: String, icon: String = "checkmark.circle", colorHex: String = "#ff5c3a") {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.createdAt = Date()
    }

    var hasTodos: Bool { !linkedTodos.isEmpty }

    var allTodosCompleted: Bool {
        hasTodos && linkedTodos.allSatisfy { $0.completed }
    }

    func isCompleted(on date: Date) -> Bool {
        let cal = Calendar.current
        return entries.contains { cal.isDate($0.date, inSameDayAs: date) }
    }

    func streak() -> Int {
        let cal = Calendar.current
        var count = 0
        let today = cal.startOfDay(for: Date())

        if entries.contains(where: { cal.isDate($0.date, inSameDayAs: today) }) {
            count = 1
            var day = cal.date(byAdding: .day, value: -1, to: today)!
            while entries.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) {
                count += 1
                guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
                day = prev
            }
        } else {
            var day = cal.date(byAdding: .day, value: -1, to: today)!
            while entries.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) {
                count += 1
                guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
                day = prev
            }
        }
        return count
    }

    func syncAutoComplete(context: ModelContext) {
        guard hasTodos else { return }
        let cal = Calendar.current
        let today = Date()
        let alreadyDone = isCompleted(on: today)

        if allTodosCompleted && !alreadyDone {
            let entry = HabitEntry(date: today, habit: self)
            context.insert(entry)
        } else if !allTodosCompleted && alreadyDone {
            if let entry = entries.first(where: { cal.isDate($0.date, inSameDayAs: today) }) {
                context.delete(entry)
            }
        }
        try? context.save()
    }
}

@Model
final class HabitEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var habit: Habit?

    init(date: Date = .now, habit: Habit? = nil) {
        self.id = UUID()
        self.date = date
        self.habit = habit
    }
}

@Model
final class TodoItem {
    var id: UUID = UUID()
    var title: String = ""
    var completed: Bool = false
    var dueDate: Date?
    var createdAt: Date = Date()
    var priority: Int = 0
    var habit: Habit?

    init(title: String, dueDate: Date? = nil, priority: Int = 0) {
        self.id = UUID()
        self.title = title
        self.dueDate = dueDate
        self.priority = priority
        self.createdAt = Date()
    }
}

@Model
final class WeeklyGoal {
    var id: UUID = UUID()
    var title: String = ""
    var targetCount: Int = 1
    var currentCount: Int = 0
    var weekStart: Date = Date()
    var createdAt: Date = Date()
    var periodRaw: String = "week"

    var period: GoalPeriod {
        get { GoalPeriod(rawValue: periodRaw) ?? .week }
        set { periodRaw = newValue.rawValue }
    }

    init(title: String, targetCount: Int = 1, period: GoalPeriod = .week) {
        self.id = UUID()
        self.title = title
        self.targetCount = targetCount
        self.periodRaw = period.rawValue
        self.createdAt = Date()

        let cal = Calendar.current
        switch period {
        case .week:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
            self.weekStart = cal.date(from: comps) ?? Date()
        case .month:
            let comps = cal.dateComponents([.year, .month], from: Date())
            self.weekStart = cal.date(from: comps) ?? Date()
        case .year:
            let comps = cal.dateComponents([.year], from: Date())
            self.weekStart = cal.date(from: comps) ?? Date()
        }
    }

    var progress: Double {
        guard targetCount > 0 else { return 0 }
        return min(Double(currentCount) / Double(targetCount), 1.0)
    }

    var isCurrentPeriod: Bool {
        let cal = Calendar.current
        switch period {
        case .week:
            return cal.isDate(weekStart, equalTo: Date(), toGranularity: .weekOfYear)
        case .month:
            return cal.isDate(weekStart, equalTo: Date(), toGranularity: .month)
        case .year:
            return cal.isDate(weekStart, equalTo: Date(), toGranularity: .year)
        }
    }

    var isCurrentWeek: Bool { isCurrentPeriod }

    var isExpired: Bool { !isCurrentPeriod }

    func renewIfNeeded() -> Bool {
        guard isExpired else { return false }
        let cal = Calendar.current
        currentCount = 0
        switch period {
        case .week:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
            weekStart = cal.date(from: comps) ?? Date()
        case .month:
            let comps = cal.dateComponents([.year, .month], from: Date())
            weekStart = cal.date(from: comps) ?? Date()
        case .year:
            let comps = cal.dateComponents([.year], from: Date())
            weekStart = cal.date(from: comps) ?? Date()
        }
        return true
    }
}

enum GoalPeriod: String, CaseIterable {
    case week, month, year

    var label: String {
        switch self {
        case .week: return "Неделя"
        case .month: return "Месяц"
        case .year: return "Год"
        }
    }

    var icon: String {
        switch self {
        case .week: return "calendar"
        case .month: return "calendar.badge.clock"
        case .year: return "star.circle"
        }
    }
}
