import Foundation
import Combine
import UserNotifications
import AVFoundation
import UIKit
import ActivityKit

class TimerManager: ObservableObject {
    static let shared = TimerManager()

    @Published var remainingTime: Int = 0
    @Published var isRunning: Bool = false
    @Published private(set) var exerciseID: String?
    @Published private(set) var exerciseName: String?

    private var timer: Timer?
    private var endDate: Date?
    private var player: AVAudioPlayer?
    private let notificationID = "rest-timer-done"
    private var cancellables = Set<AnyCancellable>()
    
    private var currentActivity: Activity<TimerAttributes>?

    private init() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.syncWithEndDate() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.timer?.invalidate(); self?.timer = nil }
            .store(in: &cancellables)
    }

    func start(seconds: Int, exerciseID: String? = nil, exerciseName: String? = nil) {
        stop()
        guard seconds > 0 else { return }

        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        let end = Date().addingTimeInterval(TimeInterval(seconds))
        endDate = end
        remainingTime = seconds
        isRunning = true

        scheduleNotification(after: seconds)
        startDisplayTimer()
        
        // Start Live Activity
        startLiveActivity(endTime: end, exerciseName: exerciseName)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        remainingTime = 0
        isRunning = false
        endDate = nil
        exerciseID = nil
        exerciseName = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        
        // End Live Activity
        endLiveActivity()
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
        } else {
            remainingTime = 0
            isRunning = false
            endDate = nil
            fireLocally()
        }
    }

    private func startDisplayTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self, let end = self.endDate else { t.invalidate(); return }
            let diff = Int(ceil(end.timeIntervalSinceNow))
            if diff > 0 {
                self.remainingTime = diff
            } else {
                self.remainingTime = 0
                self.isRunning = false
                self.endDate = nil
                t.invalidate()
                self.fireLocally()
                self.endLiveActivity()
            }
        }
    }

    private func scheduleNotification(after seconds: Int) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])

        let content = UNMutableNotificationContent()
        content.title = "Отдых окончен"
        content.body = "Время следующего сета"
        if Bundle.main.url(forResource: "radar", withExtension: "caf") != nil {
            content.sound = UNNotificationSound(named: UNNotificationSoundName("radar.caf"))
        } else {
            content.sound = .default
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("⚠️ Notification error:", error.localizedDescription) }
        }
    }

    private func fireLocally() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        if let url = Bundle.main.url(forResource: "radar", withExtension: "caf") {
            // Используем .ambient чтобы звук таймера не прерывал музыку в других приложениях
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = try? AVAudioPlayer(contentsOf: url)
            player?.play()
        }

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }
    
    // MARK: - Live Activity
    
    private func startLiveActivity(endTime: Date, exerciseName: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let attributes = TimerAttributes(exerciseName: exerciseName)
        let state = TimerAttributes.ContentState(endTime: endTime)
        let content = ActivityContent(state: state, staleDate: nil)
        
        Task {
            do {
                currentActivity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } catch {
                print("⚠️ Error starting Live Activity: \(error.localizedDescription)")
            }
        }
    }
    
    private func endLiveActivity() {
        Task {
            for activity in Activity<TimerAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            currentActivity = nil
        }
    }
}
