import Foundation
import FirebaseAI

struct ParsedFood: Identifiable {
    let id = UUID()
    var name: String
    var grams: Double
    var calories: Int
    var protein: Double
    var fat: Double
    var carbs: Double
}

final class NutritionAIService {
    static let shared = NutritionAIService()

    private var model: GenerativeModel?

    private func getModel() -> GenerativeModel {
        if let m = model { return m }
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let m = ai.generativeModel(
            modelName: "gemini-2.5-flash-lite",
            generationConfig: GenerationConfig(temperature: 0.2, maxOutputTokens: 512)
        )
        model = m
        return m
    }

    func parse(food: String, profile: BodyProfile? = nil) async throws -> [ParsedFood] {
        var profileContext = ""
        if let p = profile {
            var parts: [String] = []
            if p.weight > 0 { parts.append("вес \(String(format: "%.0f", p.weight)) кг") }
            if p.height > 0 { parts.append("рост \(String(format: "%.0f", p.height)) см") }
            if p.age > 0 { parts.append("возраст \(p.age) лет") }
            if !parts.isEmpty {
                profileContext = "\nПрофиль пользователя: \(parts.joined(separator: ", ")). Учитывай это при оценке стандартных порций."
            }
        }

        let prompt = """
        Пользователь описал что он съел: "\(food)"
        \(profileContext)

        Разбей на отдельные продукты и для каждого верни КБЖУ.
        Если порция не указана — используй стандартную порцию.
        Верни ТОЛЬКО JSON массив, без markdown, без пояснений.
        Формат:
        [{"name":"Название","grams":200,"calories":330,"protein":62.0,"fat":7.0,"carbs":0.0}]

        Правила:
        - calories — целое число (ккал)
        - protein, fat, carbs — числа с плавающей точкой (граммы)
        - grams — вес порции в граммах
        - Названия на русском языке
        - ТОЛЬКО JSON, ничего больше
        """

        let response = try await getModel().generateContent(prompt)
        guard let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw NutritionError.emptyResponse
        }

        return try decodeResponse(text)
    }

    private func decodeResponse(_ raw: String) throws -> [ParsedFood] {
        var jsonStr = raw
        if let start = raw.range(of: "["), let end = raw.range(of: "]", options: .backwards) {
            jsonStr = String(raw[start.lowerBound..<end.upperBound])
        }

        guard let data = jsonStr.data(using: .utf8) else {
            throw NutritionError.invalidJSON
        }

        struct FoodJSON: Decodable {
            let name: String
            let grams: Double?
            let calories: Int
            let protein: Double
            let fat: Double
            let carbs: Double
        }

        let items = try JSONDecoder().decode([FoodJSON].self, from: data)
        return items.map { item in
            ParsedFood(
                name: item.name,
                grams: item.grams ?? 100,
                calories: item.calories,
                protein: item.protein,
                fat: item.fat,
                carbs: item.carbs
            )
        }
    }
}

enum NutritionError: LocalizedError {
    case emptyResponse
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .emptyResponse: return "AI не вернул ответ"
        case .invalidJSON: return "Не удалось разобрать ответ AI"
        }
    }
}
