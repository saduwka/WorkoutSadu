import Foundation

// MARK: - Конфиг кардио из JSON (бандл или данные упражнения) — задаёт, какие метрики показывать на фронте.

struct CardioMetricConfig: Codable, Identifiable {
    var id: String
    var label: String
    var unit: String
    var step: Double
    var max: Double
    /// Мин. значение для отображения (по умолчанию 0)
    var min: Double?
    /// Для timeSeconds: значение в JSON в секундах, в UI показываем в минутах
    var valueType: String? // "int" | "double" | "timeSeconds" (храним сек, показ мин)
}

struct CardioConfig: Codable {
    var metrics: [CardioMetricConfig]
}

/// Загрузка пресетов: по имени упражнения возвращает конфиг метрик (из JSON в бандле или встроенный дефолт).
enum CardioPresetsLoader {
    private static let defaultConfig: CardioConfig = {
        CardioConfig(metrics: [
            CardioMetricConfig(id: "timeSeconds", label: "Время", unit: "мин", step: 1, max: 600, min: 0, valueType: "timeSeconds"),
            CardioMetricConfig(id: "distanceKm", label: "Расстояние", unit: "км", step: 0.5, max: 100, min: 0, valueType: nil),
            CardioMetricConfig(id: "stepsPerMin", label: "Средн. Ш/М", unit: "шаг/мин", step: 1, max: 300, min: 0, valueType: nil),
            CardioMetricConfig(id: "steps", label: "Ступеней", unit: "ступ.", step: 50, max: 10000, min: 0, valueType: "int"),
            CardioMetricConfig(id: "powerWatts", label: "Ср. мощность", unit: "Вт", step: 5, max: 500, min: 0, valueType: nil),
            CardioMetricConfig(id: "heartRateBpm", label: "Средний ЧСС", unit: "уд/мин", step: 1, max: 220, min: 0, valueType: "int"),
            CardioMetricConfig(id: "cadenceRpm", label: "Каденс", unit: "об/мин", step: 5, max: 200, min: 0, valueType: nil),
            CardioMetricConfig(id: "elevationMeters", label: "Набор высоты", unit: "м", step: 10, max: 2000, min: 0, valueType: nil),
        ])
    }()

    /// Конфиг для отображения кардио: по имени упражнения (из JSON) или default.
    static func config(forExerciseName name: String) -> CardioConfig {
        if let data = Bundle.main.url(forResource: "CardioPresets", withExtension: "json").flatMap({ try? Data(contentsOf: $0) }),
           let presets = try? JSONDecoder().decode([String: CardioConfig].self, from: data),
           let preset = presets[name.trimmingCharacters(in: .whitespaces)] ?? presets["default"] {
            return preset
        }
        // Встроенные пресеты по имени (без файла в бандле)
        switch name.trimmingCharacters(in: .whitespaces).lowercased() {
        case let n where n.contains("степпер") || n.contains("stepper"):
            return CardioConfig(metrics: [
                CardioMetricConfig(id: "timeSeconds", label: "Время", unit: "мин", step: 1, max: 600, min: 0, valueType: "timeSeconds"),
                CardioMetricConfig(id: "steps", label: "Ступеней", unit: "ступ.", step: 50, max: 10000, min: 0, valueType: "int"),
                CardioMetricConfig(id: "stepsPerMin", label: "Средн. Ш/М", unit: "шаг/мин", step: 1, max: 300, min: 0, valueType: nil),
                CardioMetricConfig(id: "powerWatts", label: "Ср. мощность", unit: "Вт", step: 5, max: 500, min: 0, valueType: nil),
                CardioMetricConfig(id: "heartRateBpm", label: "Средний ЧСС", unit: "уд/мин", step: 1, max: 220, min: 0, valueType: "int"),
            ])
        case let n where n.contains("дорожка") || n.contains("treadmill") || n.contains("бег"):
            return CardioConfig(metrics: [
                CardioMetricConfig(id: "timeSeconds", label: "Время", unit: "мин", step: 1, max: 600, min: 0, valueType: "timeSeconds"),
                CardioMetricConfig(id: "distanceKm", label: "Расстояние", unit: "км", step: 0.1, max: 100, min: 0, valueType: nil),
                CardioMetricConfig(id: "elevationMeters", label: "Набор высоты", unit: "м", step: 10, max: 2000, min: 0, valueType: nil),
                CardioMetricConfig(id: "heartRateBpm", label: "Средний ЧСС", unit: "уд/мин", step: 1, max: 220, min: 0, valueType: "int"),
            ])
        case let n where n.contains("вело") || n.contains("bike") || n.contains("cycling"):
            return CardioConfig(metrics: [
                CardioMetricConfig(id: "timeSeconds", label: "Время", unit: "мин", step: 1, max: 600, min: 0, valueType: "timeSeconds"),
                CardioMetricConfig(id: "distanceKm", label: "Расстояние", unit: "км", step: 0.5, max: 200, min: 0, valueType: nil),
                CardioMetricConfig(id: "powerWatts", label: "Ср. мощность", unit: "Вт", step: 5, max: 500, min: 0, valueType: nil),
                CardioMetricConfig(id: "cadenceRpm", label: "Каденс", unit: "об/мин", step: 5, max: 200, min: 0, valueType: nil),
                CardioMetricConfig(id: "heartRateBpm", label: "Средний ЧСС", unit: "уд/мин", step: 1, max: 220, min: 0, valueType: "int"),
            ])
        case let n where n.contains("гребн") || n.contains("rowing") || n.contains("эрг"):
            return CardioConfig(metrics: [
                CardioMetricConfig(id: "timeSeconds", label: "Время", unit: "мин", step: 1, max: 600, min: 0, valueType: "timeSeconds"),
                CardioMetricConfig(id: "distanceKm", label: "Расстояние", unit: "м", step: 100, max: 50000, min: 0, valueType: nil),
                CardioMetricConfig(id: "powerWatts", label: "Ср. мощность", unit: "Вт", step: 5, max: 500, min: 0, valueType: nil),
                CardioMetricConfig(id: "heartRateBpm", label: "Средний ЧСС", unit: "уд/мин", step: 1, max: 220, min: 0, valueType: "int"),
            ])
        default:
            return defaultConfig
        }
    }

    /// Строки для отображения в списках (деталь тренировки, создание и т.д.).
    static func summaryLines(exerciseName: String, values: [String: Double]) -> [String] {
        let config = config(forExerciseName: exerciseName)
        return config.metrics.compactMap { m in
            guard let v = values[m.id], v > 0 else { return nil }
            if m.valueType == "timeSeconds" { return "\(Int(v / 60)) мин" }
            if m.valueType == "int" { return "\(Int(v)) \(m.unit)" }
            return String(format: "%.1f %@", v, m.unit)
        }
    }
}
