import SwiftData
import Foundation

enum MealType: String, Codable, CaseIterable {
    case breakfast = "Завтрак"
    case lunch = "Обед"
    case dinner = "Ужин"
    case snack = "Перекус"

    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.fill"
        case .snack: return "leaf.fill"
        }
    }
}

@Model
final class MealEntry {
    var id: UUID = UUID()
    var name: String = ""
    var calories: Int = 0
    var protein: Double = 0
    var fat: Double = 0
    var carbs: Double = 0
    var grams: Double = 0
    var date: Date = Date()
    var mealTypeRaw: String = MealType.snack.rawValue

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    init(name: String, calories: Int, protein: Double, fat: Double, carbs: Double, grams: Double = 0, date: Date = .now, mealType: MealType = .snack) {
        self.id = UUID()
        self.name = name
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.grams = grams
        self.date = date
        self.mealTypeRaw = mealType.rawValue
    }
}
