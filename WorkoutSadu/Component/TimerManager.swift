import Foundation
import Combine
import UserNotifications
import UIKit
import AlarmKit
import ActivityKit
import SwiftUI
import AppIntents

@MainActor
class TimerManager: ObservableObject {
    static let shared = TimerManager()

    static let notificationID = "rest-timer-done"
    static let notificationCategoryID = "REST_TIMER"
    static let dismissActionID = "REST_TIMER_DISMISS"

    @Published var remainingTime: Int = 0
    @Published var isRunning: Bool = false
    @Published var isAlerting: Bool = false
    @Published private(set) var exerciseID: String?
    @Published private(set) var exerciseName: String?

    /// Absolute rest end time while running; nil when idle or alerting.
    private(set) var currentEndDate: Date?

    private var timer: Timer?
    private var endDate: Date?
    private var alarmID: UUID?
    private var cancellables = Set<AnyCancellable>()
    private var alarmObserveTask: Task<Void, Never>?

    private init() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.syncWithEndDate() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.timer?.invalidate(); self?.timer = nil }
            .store(in: &cancellables)

        startObservingAlarms()
    }

    func start(seconds: Int, exerciseID: String? = nil, exerciseName: String? = nil) {
        stop()
        guard seconds > 0 else { return }

        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        let end = Date().addingTimeInterval(TimeInterval(seconds))
        endDate = end
        currentEndDate = end
        remainingTime = seconds
        isRunning = true
        isAlerting = false

        startDisplayTimer()
        Task { await scheduleAlarmKit(duration: TimeInterval(seconds), exerciseName: exerciseName) }
    }

    /// - Parameter cancelAlarm: false when stop already came from AlarmKit intent.
    func stop(cancelAlarm: Bool = true) {
        timer?.invalidate()
        timer = nil
        remainingTime = 0
        isRunning = false
        isAlerting = false
        endDate = nil
        currentEndDate = nil
        exerciseID = nil
        exerciseName = nil

        let idToCancel = alarmID
        alarmID = nil
        if cancelAlarm, let id = idToCancel {
            try? AlarmManager.shared.cancel(id: id)
        }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
    }

    func adjustRemaining(by deltaSeconds: Int) {
        guard isRunning, let end = endDate else { return }
        let newEnd = end.addingTimeInterval(TimeInterval(deltaSeconds))
        let newRemaining = Int(ceil(newEnd.timeIntervalSinceNow))
        if newRemaining <= 0 {
            beginAlertLocally()
            return
        }
        endDate = newEnd
        currentEndDate = newEnd
        remainingTime = newRemaining
        startDisplayTimer()
        Task { await scheduleAlarmKit(duration: TimeInterval(newRemaining), exerciseName: exerciseName) }
    }

    func timeString() -> String {
        let minutes = remainingTime / 60
        let secs = remainingTime % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    // MARK: - Private

    private func syncWithEndDate() {
        guard let end = endDate else { return }

        let diff = Int(ceil(end.timeIntervalSinceNow))
        if diff > 0 {
            remainingTime = diff
            isRunning = true
            startDisplayTimer()
        } else if !isAlerting {
            beginAlertLocally()
        }
    }

    private func startDisplayTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            Task { @MainActor in
                guard let end = self.endDate else { t.invalidate(); return }
                let diff = Int(ceil(end.timeIntervalSinceNow))
                if diff > 0 {
                    self.remainingTime = diff
                } else {
                    t.invalidate()
                    self.beginAlertLocally()
                }
            }
        }
    }

    /// UI state when countdown hits 0; ringing is AlarmKit (or fallback notification).
    private func beginAlertLocally() {
        timer?.invalidate()
        timer = nil
        remainingTime = 0
        isRunning = false
        endDate = nil
        currentEndDate = nil
        isAlerting = true
    }

    private func startObservingAlarms() {
        alarmObserveTask?.cancel()
        alarmObserveTask = Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                guard let self else { return }
                await MainActor.run {
                    self.handleAlarmUpdates(alarms)
                }
            }
        }
    }

    private func handleAlarmUpdates(_ alarms: [Alarm]) {
        guard let id = alarmID else { return }
        if let alarm = alarms.first(where: { $0.id == id }) {
            if case .alerting = alarm.state {
                beginAlertLocally()
            }
        } else if isAlerting {
            // System Stop removed the alarm while alerting.
            stop(cancelAlarm: false)
        }
    }

    private func scheduleAlarmKit(duration: TimeInterval, exerciseName: String?) async {
        let previous = alarmID
        alarmID = nil
        if let previous {
            try? AlarmManager.shared.cancel(id: previous)
        }

        let manager = AlarmManager.shared
        do {
            let auth = try await manager.requestAuthorization()
            guard auth == .authorized else {
                scheduleFallbackNotification(after: Int(max(1, duration.rounded())))
                return
            }
        } catch {
            scheduleFallbackNotification(after: Int(max(1, duration.rounded())))
            return
        }

        let id = UUID()
        let titleText: String
        if let exerciseName, !exerciseName.isEmpty {
            titleText = "Отдых окончен · \(exerciseName)"
        } else {
            titleText = "Отдых окончен"
        }

        let countdownTitle: String
        if let exerciseName, !exerciseName.isEmpty {
            countdownTitle = exerciseName
        } else {
            countdownTitle = "ОТДЫХ"
        }

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: titleText),
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )
        let countdown = AlarmPresentation.Countdown(
            title: LocalizedStringResource(stringLiteral: countdownTitle),
            pauseButton: nil
        )
        let presentation = AlarmPresentation(alert: alert, countdown: countdown)
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: RestAlarmMetadata(exerciseName: exerciseName),
            tintColor: Color(red: 1, green: 0.36, blue: 0.23)
        )

        let config = AlarmManager.AlarmConfiguration.timer(
            duration: max(1, duration),
            attributes: attributes,
            stopIntent: StopRestAlarmIntent(alarmID: id.uuidString),
            sound: .default
        )

        do {
            _ = try await manager.schedule(id: id, configuration: config)
            alarmID = id
        } catch {
            print("⚠️ AlarmKit schedule error:", error.localizedDescription)
            scheduleFallbackNotification(after: Int(max(1, duration.rounded())))
        }
    }

    private func scheduleFallbackNotification(after seconds: Int) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])

        let content = UNMutableNotificationContent()
        content.title = "Отдых окончен"
        content.body = "Время следующего сета"
        content.categoryIdentifier = Self.notificationCategoryID
        content.userInfo = ["type": "restTimer"]
        content.interruptionLevel = .timeSensitive
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        let request = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
