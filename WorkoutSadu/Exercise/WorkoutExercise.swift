import SwiftData
import SwiftUI
import Foundation

@Model
final class WorkoutExercise {
    var id: UUID = UUID()
    var exercise: Exercise
    var timerSeconds: Int?
    var cardioTimeSeconds: Int?
    var cardioStepsPerMin: Double?
    var cardioSteps: Int?
    var cardioPowerWatts: Double?
    var cardioHeartRateBpm: Int?
    /// Гибкое хранение кардио-метрик по конфигу из JSON: ключ (id метрики) → значение.
    var cardioValuesJson: Data?
    var photo: Data?
    var distance: Double?
    var note: String? = nil
    var supersetGroup: Int? = nil
    var order: Int = 0
    var targetWeight: Double? = nil
    var targetReps: Int? = nil
    var targetSets: Int? = nil
    var workout: Workout?

    @Relationship(deleteRule: .cascade)
    var workoutSets: [WorkoutSet]

    init(
        exercise: Exercise,
        timerSeconds: Int? = nil,
        distance: Double? = nil,
        cardioTimeSeconds: Int? = nil,
        order: Int = 0
    ) {
        self.id = UUID()
        self.exercise = exercise
        self.timerSeconds = timerSeconds
        self.photo = nil
        self.distance = distance
        self.cardioTimeSeconds = cardioTimeSeconds
        self.note = nil
        self.supersetGroup = nil
        self.order = order
        self.workoutSets = []
    }

    // Convenience for summary display
    var lastSet: WorkoutSet? {
        workoutSets.sorted { $0.order < $1.order }.last
    }

    var completedSetsCount: Int {
        workoutSets.filter { $0.isCompleted }.count
    }

    func saveUIImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        self.photo = data
    }

    // MARK: - Кардио: гибкие метрики из JSON-конфига

    private static let legacyKeyToProp: [String: (get: (WorkoutExercise) -> Double?, set: (WorkoutExercise, Double) -> Void)] = [
        "timeSeconds": ({ Double($0.cardioTimeSeconds ?? 0) }, { $0.cardioTimeSeconds = Int($1) }),
        "distanceKm": ({ $0.distance }, { $0.distance = $1 }),
        "stepsPerMin": ({ $0.cardioStepsPerMin }, { $0.cardioStepsPerMin = $1 }),
        "steps": ({ $0.cardioSteps.map { Double($0) } }, { $0.cardioSteps = Int($1) }),
        "powerWatts": ({ $0.cardioPowerWatts }, { $0.cardioPowerWatts = $1 }),
        "heartRateBpm": ({ $0.cardioHeartRateBpm.map { Double($0) } }, { $0.cardioHeartRateBpm = Int($1) }),
    ]

    /// Значение кардио-метрики по id из конфига. Читает из cardioValuesJson или из legacy-полей.
    func getCardioValue(for metricId: String) -> Double? {
        if let dict = cardioValuesJson.flatMap({ try? JSONDecoder().decode([String: Double].self, from: $0) }),
           let v = dict[metricId], v > 0 { return v }
        if let (get, _) = Self.legacyKeyToProp[metricId] {
            let v = get(self)
            if let v = v, v > 0 { return v }
        }
        return nil
    }

    /// Записывает значение; синхронизирует с legacy-полями для обратной совместимости.
    func setCardioValue(for metricId: String, _ value: Double) {
        var dict = (cardioValuesJson.flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) }) ?? [:]
        if value > 0 {
            dict[metricId] = value
        } else {
            dict.removeValue(forKey: metricId)
        }
        cardioValuesJson = (try? JSONEncoder().encode(dict)) ?? cardioValuesJson
        if let (_, set) = Self.legacyKeyToProp[metricId] {
            set(self, value)
        }
    }

    /// Все сохранённые кардио-значения (из JSON + legacy) для отображения в списке/экспорте.
    func allCardioValues() -> [String: Double] {
        var out = (cardioValuesJson.flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) }) ?? [:]
        for (key, (get, _)) in Self.legacyKeyToProp {
            if out[key] == nil, let v = get(self), v > 0 { out[key] = v }
        }
        return out
    }
}
