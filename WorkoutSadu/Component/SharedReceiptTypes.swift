import Foundation

/// Transaction data saved by Share Extension to App Group; main app reads and saves to SwiftData.
struct PendingReceiptTransaction: Codable {
    var name: String
    var amount: Int
    var category: String
    var type: String
    var date: Date
}

/// Wrapper to present pending receipts sheet by identity.
struct PendingReceiptSheetItem: Identifiable {
    let id = UUID()
    let transactions: [PendingReceiptTransaction]
}

enum PendingReceiptStorage {
    static let appGroupID = "group.com.saduwka.WorkoutSadu"
    static let transactionsKey = "PendingReceiptTransactions"
    /// Raw text from Share Extension (PDF/image OCR); main app parses with AI and shows sheet.
    static let pendingTextKey = "PendingReceiptText"
    /// User already tapped "Добавить" in Share Extension — main app should save to SwiftData without showing sheet.
    static let confirmedInExtensionKey = "PendingReceiptConfirmedInExtension"
    /// Файл чека (PDF/фото) из Share Extension — ключи в UserDefaults, файл в контейнере App Group.
    static let pendingReceiptFileNameKey = "PendingReceiptFileName"
    static let pendingReceiptIsPDFKey = "PendingReceiptIsPDF"

    static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static func save(_ transactions: [PendingReceiptTransaction]) {
        userDefaults?.set(try? JSONEncoder().encode(transactions), forKey: transactionsKey)
    }

    static func load() -> [PendingReceiptTransaction]? {
        guard let data = userDefaults?.data(forKey: transactionsKey) else { return nil }
        return try? JSONDecoder().decode([PendingReceiptTransaction].self, from: data)
    }

    static func savePendingText(_ text: String) {
        userDefaults?.set(text, forKey: pendingTextKey)
    }

    static func loadPendingText() -> String? {
        userDefaults?.string(forKey: pendingTextKey)
    }

    static func clear() {
        userDefaults?.removeObject(forKey: transactionsKey)
        userDefaults?.removeObject(forKey: pendingTextKey)
        userDefaults?.removeObject(forKey: confirmedInExtensionKey)
        clearPendingReceiptFile()
    }

    /// Есть ли сохранённый файл чека из Share Extension (распознавание в приложении).
    static func hasPendingReceiptFile() -> Bool {
        userDefaults?.string(forKey: pendingReceiptFileNameKey) != nil
    }

    /// Загрузить файл чека из App Group. Возвращает (URL файла, isPDF). После обработки вызвать clearPendingReceiptFile().
    static func loadPendingReceiptFileURL() -> (URL, Bool)? {
        guard let name = userDefaults?.string(forKey: pendingReceiptFileNameKey),
              let container = containerURL else { return nil }
        let fileURL = container.appendingPathComponent(name)
        let isPDF = userDefaults?.bool(forKey: pendingReceiptIsPDFKey) ?? name.lowercased().hasSuffix(".pdf")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return (fileURL, isPDF)
    }

    static func clearPendingReceiptFile() {
        if let name = userDefaults?.string(forKey: pendingReceiptFileNameKey), let container = containerURL {
            try? FileManager.default.removeItem(at: container.appendingPathComponent(name))
        }
        userDefaults?.removeObject(forKey: pendingReceiptFileNameKey)
        userDefaults?.removeObject(forKey: pendingReceiptIsPDFKey)
    }

    /// True if user confirmed "Добавить" in Share Extension — app should insert and clear without sheet.
    static func wasConfirmedInExtension() -> Bool {
        userDefaults?.bool(forKey: confirmedInExtensionKey) ?? false
    }

    /// Сбросить только флаг «подтверждено в расширении», не трогая список транзакций (для показа листа с выбором счёта).
    static func clearConfirmedInExtensionFlag() {
        userDefaults?.set(false, forKey: confirmedInExtensionKey)
    }
}
