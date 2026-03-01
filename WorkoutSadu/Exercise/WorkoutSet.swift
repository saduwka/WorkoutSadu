import SwiftData
import Foundation

@Model
final class WorkoutSet {
    var id: UUID = UUID()
    var order: Int = 0
    var reps: Int = 10
    var weight: Double = 0
    var isCompleted: Bool = false
    var completedAt: Date? = nil

    init(order: Int, reps: Int = 10, weight: Double = 0) {
        self.id = UUID()
        self.order = order
        self.reps = reps
        self.weight = weight
        self.isCompleted = false
        self.completedAt = nil
    }
}
