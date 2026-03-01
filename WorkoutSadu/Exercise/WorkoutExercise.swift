import SwiftData
import SwiftUI
import Foundation

@Model
final class WorkoutExercise {
    var id: UUID = UUID()
    var exercise: Exercise
    var timerSeconds: Int?
    var cardioTimeSeconds: Int?
    var photo: Data?
    var distance: Double?
    var note: String? = nil
    var supersetGroup: Int? = nil
    var order: Int = 0
    var targetWeight: Double? = nil
    var targetReps: Int? = nil
    var targetSets: Int? = nil
    var workout: Workout?

    @Relationship(deleteRule: .cascade)
    var workoutSets: [WorkoutSet]

    init(
        exercise: Exercise,
        timerSeconds: Int? = nil,
        distance: Double? = nil,
        cardioTimeSeconds: Int? = nil,
        order: Int = 0
    ) {
        self.id = UUID()
        self.exercise = exercise
        self.timerSeconds = timerSeconds
        self.photo = nil
        self.distance = distance
        self.cardioTimeSeconds = cardioTimeSeconds
        self.note = nil
        self.supersetGroup = nil
        self.order = order
        self.workoutSets = []
    }

    // Convenience for summary display
    var lastSet: WorkoutSet? {
        workoutSets.sorted { $0.order < $1.order }.last
    }

    var completedSetsCount: Int {
        workoutSets.filter { $0.isCompleted }.count
    }

    func saveUIImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        self.photo = data
    }
}
