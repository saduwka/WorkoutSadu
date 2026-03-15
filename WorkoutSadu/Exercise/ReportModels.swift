import SwiftData
import Foundation

// MARK: - MoodEntry

@Model
final class MoodEntry {
    var id: UUID = UUID()
    /// Оценка 1–5 (настроение/энергия).
    var rating: Int = 3
    var note: String = ""
    var date: Date = Date()

    init(rating: Int = 3, note: String = "", date: Date = .now) {
        self.id = UUID()
        self.rating = min(5, max(1, rating))
        self.note = note
        self.date = date
    }
}

// MARK: - Report type

enum ReportType: String, Codable, CaseIterable {
    case day = "day"
    case week = "week"
    case month = "month"
    case range = "range"

    var label: String {
        switch self {
        case .day: return "День"
        case .week: return "Неделя"
        case .month: return "Месяц"
        case .range: return "Период"
        }
    }
}

// MARK: - SavedReport

@Model
final class SavedReport {
    var id: UUID = UUID()
    var reportTypeRaw: String = ReportType.day.rawValue
    var date: Date = Date()
    /// Текст комментария от LifeBro (AI).
    var aiText: String = ""
    /// Снапшот данных в виде JSON-строки для отображения в истории.
    var snapshotData: String = ""
    var createdAt: Date = Date()

    var reportType: ReportType {
        get { ReportType(rawValue: reportTypeRaw) ?? .day }
        set { reportTypeRaw = newValue.rawValue }
    }

    init(type: ReportType, date: Date, aiText: String = "", snapshotData: String = "") {
        self.id = UUID()
        self.reportTypeRaw = type.rawValue
        self.date = date
        self.aiText = aiText
        self.snapshotData = snapshotData
        self.createdAt = Date()
    }
}
