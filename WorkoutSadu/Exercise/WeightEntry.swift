import SwiftData
import Foundation

@Model
final class WeightEntry {
    var id: UUID = UUID()
    var weight: Double = 0
    var date: Date = Date()

    init(weight: Double, date: Date = .now) {
        self.id = UUID()
        self.weight = weight
        self.date = date
    }
}
