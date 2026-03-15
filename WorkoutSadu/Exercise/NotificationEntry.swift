import SwiftData
import Foundation

/// Запись уведомления, показанного пользователю (или запланированного из приложения).
/// Нужна, чтобы в приложении был экран «История уведомлений» — пользователь мог посмотреть смахнутые из центра уведомлений.
@Model
final class NotificationEntry {
    var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var date: Date = Date()
    /// Тип: nutritionSnack, nutritionWater, gymBroComment, dayReport, weekReport, monthReport
    var typeRaw: String = ""

    init(title: String, body: String, date: Date = .now, typeRaw: String) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.date = date
        self.typeRaw = typeRaw
    }
}
