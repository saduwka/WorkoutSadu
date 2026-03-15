import Foundation

/// App Group storage for Share Extension → main app. Чек передаётся файлом — распознавание в приложении.
enum ExtensionStorage {
    static let appGroupID = "group.com.saduwka.WorkoutSadu"
    static let pendingTextKey = "PendingReceiptText"
    static let transactionsKey = "PendingReceiptTransactions"
    static let confirmedInExtensionKey = "PendingReceiptConfirmedInExtension"
    static let pendingReceiptFileNameKey = "PendingReceiptFileName"
    static let pendingReceiptIsPDFKey = "PendingReceiptIsPDF"
    private static let receiptFileName = "PendingReceipt"

    static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static func savePendingText(_ text: String) {
        userDefaults?.set(text, forKey: pendingTextKey)
    }

    /// Сохранить файл чека (PDF или изображение) в App Group — приложение распознает и покажет лист.
    static func savePendingReceiptFile(data: Data, isPDF: Bool) -> Bool {
        guard let container = containerURL else { return false }
        let ext = isPDF ? "pdf" : "jpg"
        let fileURL = container.appendingPathComponent("\(receiptFileName).\(ext)")
        do {
            try data.write(to: fileURL)
            userDefaults?.set("\(receiptFileName).\(ext)", forKey: pendingReceiptFileNameKey)
            userDefaults?.set(isPDF, forKey: pendingReceiptIsPDFKey)
            return true
        } catch {
            return false
        }
    }

    /// Сохранить транзакции после нажатия «Добавить» в расширении — приложение только сохранит в SwiftData без показа листа.
    static func saveConfirmedTransactions(_ items: [ParsedReceiptItem]) {
        let list = items.map { p in
            ExtensionPendingTransaction(name: p.name, amount: p.amount, category: p.category, type: p.type, date: p.date)
        }
        userDefaults?.set(try? JSONEncoder().encode(list), forKey: transactionsKey)
        userDefaults?.set(true, forKey: confirmedInExtensionKey)
    }
}

struct ExtensionPendingTransaction: Codable {
    var name: String
    var amount: Int
    var category: String
    var type: String
    var date: Date
}
