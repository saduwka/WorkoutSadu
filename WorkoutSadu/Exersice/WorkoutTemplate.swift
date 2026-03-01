import SwiftData
import Foundation

@Model
final class WorkoutTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade)
    var exercises: [TemplateExercise]

    init(name: String, exercises: [TemplateExercise] = []) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.exercises = exercises
    }
}

@Model
final class TemplateExercise {
    var id: UUID = UUID()
    var order: Int = 0
    var exerciseName: String = ""
    var bodyPart: String = ""
    var timerSeconds: Int? = nil
    var defaultSets: Int = 3
    var defaultReps: Int = 10
    var defaultWeight: Double = 0

    init(
        order: Int,
        exerciseName: String,
        bodyPart: String,
        timerSeconds: Int? = nil,
        defaultSets: Int = 3,
        defaultReps: Int = 10,
        defaultWeight: Double = 0
    ) {
        self.id = UUID()
        self.order = order
        self.exerciseName = exerciseName
        self.bodyPart = bodyPart
        self.timerSeconds = timerSeconds
        self.defaultSets = defaultSets
        self.defaultReps = defaultReps
        self.defaultWeight = defaultWeight
    }
}
