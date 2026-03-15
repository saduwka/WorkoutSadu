import SwiftData
import Foundation

/// Цель по телу: для подбора калорий и советов Life Bro.
enum BodyGoal: String, Codable, CaseIterable {
    case loseWeight = "lose_weight"       // похудеть
    case gainMuscle = "gain_muscle"      // набрать мышечную массу
    case maintain = "maintain"           // удержать
    case gain = "gain"                   // набрать вес

    var title: String {
        switch self {
        case .loseWeight: return "Похудеть"
        case .gainMuscle: return "Набрать мышечную массу"
        case .maintain: return "Удержать"
        case .gain: return "Набрать вес"
        }
    }
}

@Model
final class BodyProfile {
    var weight: Double = 0
    var height: Double = 0
    var age: Int = 0
    /// Если задана — возраст считается из неё (актуально «почти 30»).
    var birthDate: Date? = nil
    var restingHeartRate: Int = 0
    var bodyFatPercent: Double? = nil
    /// Цель: похудеть, набрать мышцы, удержать, набрать вес.
    var goalRaw: String = ""
    var updatedAt: Date = Date()

    init(
        weight: Double = 0,
        height: Double = 0,
        age: Int = 0,
        birthDate: Date? = nil,
        restingHeartRate: Int = 0,
        bodyFatPercent: Double? = nil,
        goalRaw: String = "",
        targetWeightKg: Double = 0
    ) {
        self.weight = weight
        self.height = height
        self.age = age
        self.birthDate = birthDate
        self.restingHeartRate = restingHeartRate
        self.bodyFatPercent = bodyFatPercent
        self.goalRaw = goalRaw
        self.targetWeightKg = targetWeightKg
        self.updatedAt = Date()
    }

    /// Возраст в полных годах: из даты рождения или ручной ввод.
    var effectiveAge: Int {
        if let d = birthDate {
            return Calendar.current.dateComponents([.year], from: d, to: Date()).year ?? 0
        }
        return age
    }

    var goal: BodyGoal? {
        BodyGoal(rawValue: goalRaw)
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
        guard effectiveAge > 0 else { return nil }
        return Int(208 - 0.7 * Double(effectiveAge))
    }

    // Ideal weight range (Devine formula), кг
    var idealWeightRange: ClosedRange<Double>? {
        guard height > 0 else { return nil }
        let base = height - 152.4
        let ideal = 50 + 0.9 * base
        return (ideal - 5)...(ideal + 5)
    }

    /// Целевой вес, заданный пользователем (кг). 0 = не задан.
    var targetWeightKg: Double = 0

    /// Рекомендуемая цель по весу исходя из цели (похудеть/набор/удержать) и нормы по росту.
    var suggestedTargetWeight: Double? {
        guard height > 0, weight > 0, let range = idealWeightRange else { return nil }
        let mid = (range.lowerBound + range.upperBound) / 2
        switch goal {
        case .loseWeight:
            return min(weight - 1, range.upperBound)
        case .gainMuscle, .gain:
            return max(weight + 1, range.lowerBound)
        case .maintain:
            return weight
        case nil:
            return mid
        }
    }

    /// Показываемая цель по весу: заданная пользователем или рекомендуемая.
    var displayTargetWeight: Double? {
        if targetWeightKg > 0 { return targetWeightKg }
        return suggestedTargetWeight
    }

    /// Разница текущего веса и цели (положительная = нужно сбросить, отрицательная = набрать). nil если нет цели.
    var weightDeltaFromTarget: Double? {
        guard let target = displayTargetWeight, weight > 0 else { return nil }
        return weight - target
    }
}
