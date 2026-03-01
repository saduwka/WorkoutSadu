import SwiftData
import Foundation

enum FinanceCategory: String, CaseIterable, Codable {
    case food = "Еда"
    case transport = "Транспорт"
    case fuel = "Топливо"
    case communication = "Связь"
    case subscriptions = "Подписки"
    case utilities = "Коммунальные"
    case health = "Здоровье"
    case clothing = "Одежда"
    case shopping = "Покупки"
    case entertainment = "Развлечения"
    case transfers = "Переводы"
    case income = "Доход"
    case other = "Другое"

    var icon: String {
        switch self {
        case .food:           return "fork.knife"
        case .transport:      return "car.fill"
        case .fuel:           return "fuelpump.fill"
        case .communication:  return "phone.fill"
        case .subscriptions:  return "repeat"
        case .utilities:      return "house.fill"
        case .health:         return "heart.fill"
        case .clothing:       return "tshirt.fill"
        case .shopping:       return "bag.fill"
        case .entertainment:  return "gamecontroller.fill"
        case .transfers:      return "arrow.left.arrow.right"
        case .income:         return "arrow.down.circle.fill"
        case .other:          return "ellipsis.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .food:           return "#ff5c3a"
        case .transport:      return "#5b8cff"
        case .fuel:           return "#ffb830"
        case .communication:  return "#a855f7"
        case .subscriptions:  return "#f472b6"
        case .utilities:      return "#6366f1"
        case .health:         return "#ef4444"
        case .clothing:       return "#ec4899"
        case .shopping:       return "#8b5cf6"
        case .entertainment:  return "#f59e0b"
        case .transfers:      return "#6b7280"
        case .income:         return "#3aff9e"
        case .other:          return "#6b6b80"
        }
    }
}

enum FinanceType: String, CaseIterable, Codable {
    case expense = "Расход"
    case income = "Доход"
}

@Model
final class FinanceAccount {
    var id: UUID = UUID()
    var name: String = ""
    var balance: Int = 0
    var icon: String = "creditcard.fill"
    var colorHex: String = "#5b8cff"
    var createdAt: Date = Date()

    init(name: String, balance: Int = 0, icon: String = "creditcard.fill", colorHex: String = "#5b8cff") {
        self.id = UUID()
        self.name = name
        self.balance = balance
        self.icon = icon
        self.colorHex = colorHex
        self.createdAt = Date()
    }
}

@Model
final class FinanceTransaction {
    var id: UUID = UUID()
    var name: String = ""
    var amount: Int = 0
    var categoryRaw: String = FinanceCategory.other.rawValue
    var typeRaw: String = FinanceType.expense.rawValue
    var date: Date = Date()
    var accountID: UUID?

    var category: FinanceCategory {
        get { FinanceCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var type: FinanceType {
        get { FinanceType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    init(name: String, amount: Int, category: FinanceCategory = .other, type: FinanceType = .expense, date: Date = .now, accountID: UUID? = nil) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.categoryRaw = category.rawValue
        self.typeRaw = type.rawValue
        self.date = date
        self.accountID = accountID
    }
}
