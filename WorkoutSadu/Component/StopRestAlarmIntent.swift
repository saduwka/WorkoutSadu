import AppIntents
import AlarmKit
import Foundation

/// Стоп системного будильника отдыха без открытия приложения.
struct StopRestAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Отключить"
    static var description = IntentDescription("Остановить будильник отдыха между подходами")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {
        alarmID = ""
    }

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: id)
        }
        await MainActor.run {
            TimerManager.shared.stop(cancelAlarm: false)
        }
        return .result()
    }
}
