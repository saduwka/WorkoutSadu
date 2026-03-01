import Foundation
import SwiftData

enum WidgetDataManager {
    static let appGroupID = "group.com.saduwka.WorkoutSadu"
    static let suiteName = appGroupID

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func sync(context: ModelContext) {
        guard let defaults = defaults else { return }

        let workoutDescriptor = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let exerciseDescriptor = FetchDescriptor<Exercise>()

        guard let workouts = try? context.fetch(workoutDescriptor) else { return }
        let finished = workouts.filter { $0.finishedAt != nil }

        // Streak
        let streak = GamificationManager.weeklyStreak(workouts: workouts)
        defaults.set(streak.current, forKey: "widgetStreak")
        defaults.set(streak.completedThisWeek, forKey: "widgetThisWeek")
        defaults.set(streak.goalPerWeek, forKey: "widgetWeeklyGoal")

        // Days since last workout
        if let last = finished.first?.date {
            let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            defaults.set(days, forKey: "widgetDaysSince")
            defaults.set(last.timeIntervalSince1970, forKey: "widgetLastDate")
        } else {
            defaults.set(-1, forKey: "widgetDaysSince")
            defaults.removeObject(forKey: "widgetLastDate")
        }

        // Total workouts
        defaults.set(finished.count, forKey: "widgetTotalWorkouts")

        // XP & Level
        let xp = GamificationManager.xpTotal(workouts: workouts)
        let levelInfo = GamificationManager.level(xp: xp)
        defaults.set(xp, forKey: "widgetXP")
        defaults.set(levelInfo.level, forKey: "widgetLevel")
        defaults.set(levelInfo.name, forKey: "widgetLevelName")
        defaults.set(levelInfo.emoji, forKey: "widgetLevelEmoji")

        // Best PR
        if let exercises = try? context.fetch(exerciseDescriptor) {
            var bestExName = ""
            var bestWeight = 0.0
            for ex in exercises {
                guard ex.bodyPart != "Кардио" else { continue }
                if let w = PRManager.bestWeight(for: ex, in: context), w > bestWeight {
                    bestWeight = w
                    bestExName = ex.name
                }
            }
            if bestWeight > 0 {
                defaults.set(bestExName, forKey: "widgetPRExercise")
                defaults.set(bestWeight, forKey: "widgetPRWeight")
            }
        }

        // Muscle statuses
        let statuses = GamificationManager.muscleStatuses(workouts: workouts)
        var muscleData: [[String: Any]] = []
        for s in statuses {
            muscleData.append([
                "name": s.name,
                "emoji": s.emoji,
                "daysAgo": s.daysAgo ?? -1,
                "state": s.state == .done ? "done" : s.state == .warning ? "warning" : "missed"
            ])
        }
        defaults.set(muscleData, forKey: "widgetMuscles")

        // Week volume
        let weekStart = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let weekWorkouts = finished.filter { $0.date >= weekStart }
        let weekVolume = weekWorkouts.flatMap { $0.workoutExercises }
            .flatMap { $0.workoutSets }
            .filter { $0.isCompleted }
            .reduce(0.0) { $0 + $1.weight * Double($1.reps) }
        defaults.set(weekVolume, forKey: "widgetWeekVolume")

        // Week day map (Mon=0 ... Sun=6)
        var weekDays: [Int] = []
        for w in weekWorkouts {
            let wd = (Calendar.current.component(.weekday, from: w.date) + 5) % 7
            if !weekDays.contains(wd) { weekDays.append(wd) }
        }
        defaults.set(weekDays, forKey: "widgetWeekDays")

        defaults.synchronize()
    }
}
