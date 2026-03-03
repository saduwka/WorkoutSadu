import Foundation

/// App Group storage for Share Extension → main app. Same group ID and keys as main app.
enum ExtensionStorage {
    static let appGroupID = "group.com.saduwka.WorkoutSadu"
    static let pendingTextKey = "PendingReceiptText"
    static let transactionsKey = "PendingReceiptTransactions"
    static let confirmedInExtensionKey = "PendingReceiptConfirmedInExtension"

    static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func savePendingText(_ text: String) {
        userDefaults?.set(text, forKey: pendingTextKey)
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
