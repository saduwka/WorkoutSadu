import SwiftData
import SwiftUI

@Model
final class Workout {
    var id: UUID = UUID()
    var name: String = ""
    var date: Date = Date()
    var startedAt: Date? = nil
    var finishedAt: Date? = nil
    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    var workoutExercises: [WorkoutExercise]

    init(
        name: String,
        date: Date = .now,
        workoutExercises: [WorkoutExercise] = []
    ) {
        self.id = UUID()
        self.name = name
        self.date = date
        self.startedAt = nil
        self.finishedAt = nil
        self.workoutExercises = workoutExercises
    }

    var durationSeconds: Int? {
        guard let start = startedAt, let end = finishedAt else { return nil }
        return Int(end.timeIntervalSince(start))
    }

    var durationFormatted: String? {
        guard let secs = durationSeconds, secs > 0 else { return nil }
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m) min"
    }
}

