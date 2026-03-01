import SwiftData
import Foundation

@Model
final class BodyProfile {
    var weight: Double = 0
    var height: Double = 0
    var age: Int = 0
    var restingHeartRate: Int = 0
    var bodyFatPercent: Double? = nil
    var updatedAt: Date = Date()

    init(
        weight: Double = 0,
        height: Double = 0,
        age: Int = 0,
        restingHeartRate: Int = 0,
        bodyFatPercent: Double? = nil
    ) {
        self.weight = weight
        self.height = height
        self.age = age
        self.restingHeartRate = restingHeartRate
        self.bodyFatPercent = bodyFatPercent
        self.updatedAt = Date()
    }

    // BMI
    var bmi: Double? {
        guard height > 0, weight > 0 else { return nil }
        let heightM = height / 100
        return weight / (heightM * heightM)
    }

    var bmiCategory: String {
        guard let bmi else { return "—" }
        switch bmi {
        case ..<18.5: return "Недовес"
        case 18.5..<25: return "Норма"
        case 25..<30: return "Избыток веса"
        default: return "Ожирение"
        }
    }

    // Max heart rate (Tanaka formula)
    var maxHeartRate: Int? {
        guard age > 0 else { return nil }
        return Int(208 - 0.7 * Double(age))
    }

    // Ideal weight range (Devine formula)
    var idealWeightRange: ClosedRange<Double>? {
        guard height > 0 else { return nil }
        let base = height - 152.4
        let ideal = 50 + 0.9 * base
        return (ideal - 5)...(ideal + 5)
    }
}
