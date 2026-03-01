import Foundation

struct CalorieCalculator {

    /// MET values by body part
    private static func met(for bodyPart: String) -> Double {
        switch bodyPart {
        case BodyPart.cardio.rawValue: return 7.0
        case BodyPart.legs.rawValue:   return 6.0
        default:                       return 5.0
        }
    }

    /// Estimate calories burned in a single workout.
    /// Uses Mifflin-St Jeor BMR for age/height correction when available.
    static func burned(workout: Workout, profile: BodyProfile?) -> Int {
        let weight = profile?.weight ?? 70
        guard weight > 0,
              let start = workout.startedAt,
              let end = workout.finishedAt else { return 0 }

        let hours = end.timeIntervalSince(start) / 3600.0
        guard hours > 0 else { return 0 }

        let exercises = workout.workoutExercises
        guard !exercises.isEmpty else { return 0 }

        let avgMET = exercises
            .map { met(for: $0.exercise.bodyPart) }
            .reduce(0, +) / Double(exercises.count)

        // Age/height correction via BMR ratio (Mifflin-St Jeor, male approximation)
        let bmrFactor: Double
        if let p = profile, p.height > 0, p.age > 0 {
            let bmr = 10.0 * p.weight + 6.25 * p.height - 5.0 * Double(p.age) + 5.0
            let standardBMR = 10.0 * weight + 6.25 * 175 - 5.0 * 25 + 5.0
            bmrFactor = bmr / standardBMR
        } else {
            bmrFactor = 1.0
        }

        return Int(avgMET * weight * hours * bmrFactor)
    }

    /// Total calories burned across workouts on a given day.
    static func burnedOnDay(_ date: Date, workouts: [Workout], profile: BodyProfile?) -> Int {
        let cal = Calendar.current
        return workouts
            .filter { cal.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + burned(workout: $1, profile: profile) }
    }

    /// Estimated daily calorie target (Mifflin-St Jeor TDEE).
    static func dailyTarget(profile: BodyProfile?, activityLevel: Double = 1.55) -> Int? {
        guard let p = profile, p.weight > 0, p.height > 0, p.age > 0 else { return nil }
        let bmr = 10.0 * p.weight + 6.25 * p.height - 5.0 * Double(p.age) + 5.0
        return Int(bmr * activityLevel)
    }
}
