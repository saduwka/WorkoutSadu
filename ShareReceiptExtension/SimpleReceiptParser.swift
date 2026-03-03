import Foundation

/// Простой парсер чека без AI: ищет итоговую сумму в тексте (Kaspi, типичные чеки).
struct SimpleReceiptParser {
    /// Извлекает одну транзакцию по итоговой сумме из текста чека.
    static func parse(_ text: String) -> ParsedReceiptItem? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: " ")
        let lower = cleaned.lowercased()

        // Паттерны перед суммой: "итого", "к оплате", "сумма", "всего", "total"
        let patterns = [
            #"(?:итого|к оплате|всего|сумма к оплате|total)\s*[:\s]*(\d+(?:[.,]\d{2})?)"#,
            #"(\d+(?:[.,]\d{2})?)\s*(?:тг|тенге|₸|kzt)"#,
            #"(?:оплачено|paid|amount)\s*[:\s]*(\d+(?:[.,]\d{2})?)"#,
            #"\n\s*(\d{3,}(?:[.,]\d{2})?)\s*\n"#, // число на отдельной строке (часто итог)
        ]
        let nsString = lower as NSString
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: lower) else { continue }
            var numStr = String(lower[range]).replacingOccurrences(of: ",", with: ".")
            numStr = numStr.replacingOccurrences(of: " ", with: "")
            guard let amount = Int(numStr.filter(\.isNumber)), amount > 0 else { continue }
            let name = extractMerchantName(from: cleaned) ?? "Оплата по чеку"
            return ParsedReceiptItem(
                name: name,
                amount: amount,
                category: "Другое",
                type: "Расход",
                date: Date()
            )
        }
        // Последнее большое число в тексте (часто итог)
        if let last = lastReasonableAmount(in: cleaned) {
            return ParsedReceiptItem(
                name: extractMerchantName(from: cleaned) ?? "Оплата по чеку",
                amount: last,
                category: "Другое",
                type: "Расход",
                date: Date()
            )
        }
        return nil
    }

    private static func extractMerchantName(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for line in lines.prefix(5) {
            let l = line
            let digitCount = l.filter(\.isNumber).count
            if l.count > 2, l.count < 60, digitCount < 3 || Double(digitCount) / Double(l.count) < 0.5 {
                let cleaned = l.filter { $0.isLetter || $0.isWhitespace || $0 == "-" }.trimmingCharacters(in: .whitespaces)
                if cleaned.count > 2 { return String(cleaned.prefix(40)) }
            }
        }
        return nil
    }

    private static func lastReasonableAmount(in text: String) -> Int? {
        let pattern = #"\d{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        let numbers = matches.compactMap { match -> Int? in
            guard let r = Range(match.range, in: text) else { return nil }
            return Int(text[r])
        }.filter { $0 >= 100 && $0 <= 100_000_000 }
        return numbers.last
    }
}

struct ParsedReceiptItem {
    var name: String
    var amount: Int
    var category: String
    var type: String
    var date: Date
}
