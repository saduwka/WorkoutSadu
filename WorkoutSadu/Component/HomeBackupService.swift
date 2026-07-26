import Foundation
import SwiftData
import UserNotifications
import BackgroundTasks

/// Второй канал бэкапа: Raspberry Pi по домашней LAN (авто), Tailscale — fallback при недоступности LAN и вручную.
final class HomeBackupService {
    static let shared = HomeBackupService()

    static let bgTaskIdentifier = "com.saduwka.WorkoutSadu.homeBackup"
    private static let notificationId = "home-backup-failed"

    private enum Keys {
        static let enabled = "HomeBackup.enabled"
        static let lanURL = "HomeBackup.lanBaseURL"
        static let tailscaleURL = "HomeBackup.tailscaleBaseURL"
        static let token = "HomeBackup.token"
        static let lastSuccess = "HomeBackup.lastSuccessDate"
        static let lastFailNotify = "HomeBackup.lastFailNotifyDate"
    }

    private let successInterval: TimeInterval = 20 * 60 * 60
    private let catchUpInterval: TimeInterval = 24 * 60 * 60
    private let failNotifyCooldown: TimeInterval = 20 * 60 * 60
    private let uploadTimeout: TimeInterval = 8

    private init() {}

    // MARK: - Settings

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.enabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.enabled) }
    }

    var lanBaseURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: Keys.lanURL) ?? ""
            return stored.isEmpty ? "http://192.168.10.30:8787" : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lanURL) }
    }

    var tailscaleBaseURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: Keys.tailscaleURL) ?? ""
            return stored.isEmpty ? "http://100.99.85.87:8787" : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.tailscaleURL) }
    }

    var token: String {
        get { UserDefaults.standard.string(forKey: Keys.token) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.token) }
    }

    var lastSuccessDate: Date? {
        UserDefaults.standard.object(forKey: Keys.lastSuccess) as? Date
    }

    // MARK: - BGTask

    static func registerBGTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            scheduleNextBGTask()
            let context = NotificationDelegate.shared.modelContext
            guard let context else {
                refresh.setTaskCompleted(success: false)
                return
            }
            let incomplete = refresh
            Task { @MainActor in
                await HomeBackupService.shared.tryHomeExportIfNeeded(context: context, preferNightWindow: true)
                incomplete.setTaskCompleted(success: true)
            }
        }
    }

    static func scheduleNextBGTask() {
        let request = BGAppRefreshTaskRequest(identifier: bgTaskIdentifier)
        request.earliestBeginDate = nextThreeAM()
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[HomeBackup] BG schedule failed: \(error.localizedDescription)")
        }
    }

    private static func nextThreeAM(from date: Date = Date()) -> Date {
        var cal = Calendar.current
        cal.timeZone = .current
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = 3
        comps.minute = 0
        comps.second = 0
        let today3 = cal.date(from: comps) ?? date
        if today3 > date {
            return today3
        }
        return cal.date(byAdding: .day, value: 1, to: today3) ?? today3.addingTimeInterval(24 * 60 * 60)
    }

    // MARK: - Auto / Manual

    /// Авто: LAN, при ошибке — Tailscale. Ночное окно 02–05 или утренний догон, если >24 ч без успеха.
    @MainActor
    func tryHomeExportIfNeeded(context: ModelContext, preferNightWindow: Bool = false) async {
        guard isEnabled else { return }
        guard !token.isEmpty else { return }
        let lan = normalizedBaseURL(lanBaseURL)
        let ts = normalizedBaseURL(tailscaleBaseURL)
        guard !lan.isEmpty || !ts.isEmpty else { return }

        if let last = lastSuccessDate, Date().timeIntervalSince(last) < successInterval {
            return
        }

        let hour = Calendar.current.component(.hour, from: Date())
        let inNightWindow = (2...4).contains(hour)
        let needsCatchUp: Bool = {
            guard let last = lastSuccessDate else { return true }
            return Date().timeIntervalSince(last) >= catchUpInterval
        }()

        if preferNightWindow {
            guard inNightWindow || needsCatchUp else { return }
        } else {
            // При открытии приложения — догон, если давно не было успеха; ночью тоже пробуем.
            guard inNightWindow || needsCatchUp else { return }
        }

        let data: Data
        do {
            data = try makePayloadData(context: context)
        } catch {
            print("[HomeBackup] Auto payload failed: \(error.localizedDescription)")
            return
        }

        if !lan.isEmpty {
            do {
                try await putBackup(data: data, baseURLString: lan)
                saveLastSuccess()
                return
            } catch {
                print("[HomeBackup] Auto LAN failed, trying Tailscale: \(error.localizedDescription)")
            }
        }

        guard !ts.isEmpty else {
            notifyTailscaleNeeded()
            return
        }

        do {
            try await putBackup(data: data, baseURLString: ts)
            saveLastSuccess()
        } catch {
            print("[HomeBackup] Auto Tailscale failed: \(error.localizedDescription)")
            notifyTailscaleNeeded()
        }
    }

    /// Ручной: сначала LAN, при ошибке — Tailscale.
    @MainActor
    func forceHomeExport(context: ModelContext) async throws {
        guard !token.isEmpty else {
            throw homeError("Укажи токен бэкапа")
        }
        let lan = normalizedBaseURL(lanBaseURL)
        let ts = normalizedBaseURL(tailscaleBaseURL)
        guard !lan.isEmpty || !ts.isEmpty else {
            throw homeError("Настрой LAN или Tailscale URL в профиле")
        }

        let data = try makePayloadData(context: context)

        if !lan.isEmpty {
            do {
                try await putBackup(data: data, baseURLString: lan)
                saveLastSuccess()
                return
            } catch {
                print("[HomeBackup] Manual LAN failed, trying Tailscale: \(error.localizedDescription)")
            }
        }

        guard !ts.isEmpty else {
            throw homeError("LAN недоступен. Включи Tailscale и укажи Tailscale URL, либо проверь домашний IP")
        }
        try await putBackup(data: data, baseURLString: ts)
        saveLastSuccess()
    }

    // MARK: - Upload

    @MainActor
    private func makePayloadData(context: ModelContext) throws -> Data {
        let built = try BackupPayloadBuilder.build(context: context)
        guard !built.payload.isEffectivelyEmpty else {
            throw homeError("Нечего сохранять — в приложении нет данных для бэкапа")
        }
        return built.data
    }

    private func putBackup(data: Data, baseURLString: String) async throws {
        var base = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/backup") else {
            throw homeError("Некорректный URL")
        }
        try await performPut(url: url, data: data)
    }

    private func performPut(url: URL, data: Data) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = uploadTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw homeError("Нет ответа от Raspberry Pi")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: responseData, encoding: .utf8) ?? ""
            throw homeError("Ошибка Pi (\(http.statusCode)): \(body.prefix(120))")
        }
    }

    private func normalizedBaseURL(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveLastSuccess() {
        UserDefaults.standard.set(Date(), forKey: Keys.lastSuccess)
    }

    private func homeError(_ message: String) -> NSError {
        NSError(domain: "HomeBackup", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: - Notification

    private func notifyTailscaleNeeded() {
        if let last = UserDefaults.standard.object(forKey: Keys.lastFailNotify) as? Date,
           Date().timeIntervalSince(last) < failNotifyCooldown {
            return
        }
        UserDefaults.standard.set(Date(), forKey: Keys.lastFailNotify)

        let content = UNMutableNotificationContent()
        content.title = "Бэкап на Raspberry Pi"
        content.body = "Домашняя сеть недоступна. Включи Tailscale и сделай бэкап в приложении (Профиль → Сохранить на Raspberry Pi)."
        content.sound = .default
        content.userInfo = ["type": "homeBackupFailed"]

        let request = UNNotificationRequest(
            identifier: Self.notificationId,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[HomeBackup] Notify failed: \(error.localizedDescription)")
            }
        }
    }
}
