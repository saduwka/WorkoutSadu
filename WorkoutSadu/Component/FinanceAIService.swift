import Foundation
import FirebaseAI

struct ParsedFinanceEntry: Identifiable {
    let id = UUID()
    var name: String
    var amount: Int
    var category: String
    var type: String
    var date: Date?
}

final class FinanceAIService {
    static let shared = FinanceAIService()

    private var model: GenerativeModel?

    private func getModel() -> GenerativeModel {
        if let m = model { return m }
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let m = ai.generativeModel(
            modelName: "gemini-2.5-flash-lite",
            generationConfig: GenerationConfig(temperature: 0.1, maxOutputTokens: 1024)
        )
        model = m
        return m
    }

    func parse(text: String) async throws -> [ParsedFinanceEntry] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())

        let prompt = """
        Проанализируй текст и извлеки ВСЕ финансовые транзакции.
        Текст может быть разговорным и содержать несколько транзакций.

        Примеры:
        - "хлеб 500 парковка 300" → 2 транзакции
        - "вчера бензин 2000 и сегодня обед 500" → 2 транзакции
        - "зарплата 500000" → 1 транзакция типа "Доход"

        Сегодняшняя дата: \(today)

        Для каждой транзакции определи:
        1. name — краткое название (1-3 слова)
        2. amount — сумма (целое число). "тыща" = 1000, "две" = 2000 и т.д.
        3. category — одна из: Еда, Транспорт, Топливо, Связь, Подписки, Коммунальные, Здоровье, Одежда, Покупки, Развлечения, Переводы, Доход, Другое
        4. type — "Доход" или "Расход"
        5. date — дата в формате YYYY-MM-DD ("вчера", "сегодня" → конвертируй, иначе \(today))

        Верни ТОЛЬКО JSON массив, без markdown:
        [{"name":"кофе","amount":500,"category":"Еда","type":"Расход","date":"2026-03-01"}]

        Текст: \(text)
        """

        let response = try await getModel().generateContent(prompt)
        guard let raw = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw FinanceAIError.emptyResponse
        }
        return try decodeResponse(raw)
    }

    func parseReceipt(text: String) async throws -> [ParsedFinanceEntry] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())

        let prompt = """
        Это текст кассового чека, распознанный через OCR. Извлеки данные:

        Сегодняшняя дата: \(today)

        Верни JSON массив с одной или несколькими транзакциями:
        [{"name":"Название магазина или описание","amount":итоговая_сумма,"category":"категория","type":"Расход","date":"YYYY-MM-DD"}]

        Правила:
        - amount — итоговая сумма чека (целое число)
        - Если есть название магазина — используй его как name
        - category: определи по содержимому (продукты → Еда, аптека → Здоровье и т.д.)
        - Допустимые category: Еда, Транспорт, Топливо, Связь, Подписки, Коммунальные, Здоровье, Одежда, Покупки, Развлечения, Переводы, Другое
        - Если в чеке есть дата — используй её, иначе \(today)
        - Верни ТОЛЬКО JSON, без markdown

        Текст чека:
        \(text)
        """

        let response = try await getModel().generateContent(prompt)
        guard let raw = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw FinanceAIError.emptyResponse
        }
        return try decodeResponse(raw)
    }

    private func decodeResponse(_ raw: String) throws -> [ParsedFinanceEntry] {
        var jsonStr = raw
        if let start = raw.range(of: "["), let end = raw.range(of: "]", options: .backwards) {
            jsonStr = String(raw[start.lowerBound..<end.upperBound])
        }

        guard let data = jsonStr.data(using: .utf8) else {
            throw FinanceAIError.invalidJSON
        }

        struct EntryJSON: Decodable {
            let name: String
            let amount: Int
            let category: String?
            let type: String?
            let date: String?
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        let items = try JSONDecoder().decode([EntryJSON].self, from: data)
        return items.map { item in
            ParsedFinanceEntry(
                name: item.name,
                amount: item.amount,
                category: item.category ?? "Другое",
                type: item.type ?? "Расход",
                date: item.date.flatMap { df.date(from: $0) }
            )
        }
    }
}

enum FinanceAIError: LocalizedError {
    case emptyResponse
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .emptyResponse: return "AI не вернул ответ"
        case .invalidJSON: return "Не удалось разобрать ответ AI"
        }
    }
}
