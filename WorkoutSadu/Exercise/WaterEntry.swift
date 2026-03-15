import SwiftData
import Foundation

@Model
final class WaterEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    /// Объём в миллилитрах (стакан ≈ 250 мл).
    var amountML: Int = 0

    init(date: Date = .now, amountML: Int) {
        self.id = UUID()
        self.date = date
        self.amountML = max(0, amountML)
    }
}
