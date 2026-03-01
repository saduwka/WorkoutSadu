import SwiftData
import Foundation

enum PRType: String {
    case weight = "Рекорд веса"
    case volume = "Рекорд объёма"
}

struct PRResult {
    let types: [PRType]
    let newMaxWeight: Double?
    let newMaxVolume: Double?
}

struct PRDetailInfo: Identifiable {
    let id: UUID
    let exerciseName: String
    let bodyPart: String
    let bestWeight: Double
    let bestWeightReps: Int
    let bestWeightDate: Date
    let bestWeightWorkoutName: String
    let bestVolume: Double
    let bestVolumeWeight: Double
    let bestVolumeReps: Int
    let bestVolumeDate: Date
    let totalSets: Int
    let totalWorkouts: Int
    let weightHistory: [(date: Date, weight: Double)]
}

struct PRManager {
    static func check(
        set: WorkoutSet,
        exercise: Exercise,
        in context: ModelContext
    ) -> PRResult? {
        guard set.isCompleted, set.weight > 0 else { return nil }

        let exerciseID = exercise.id
        let predicate = #Predicate<WorkoutExercise> { $0.exercise.id == exerciseID }
        let descriptor = FetchDescriptor(predicate: predicate)

        guard let allWE = try? context.fetch(descriptor) else { return nil }

        let historicalSets = allWE
            .flatMap(\.workoutSets)
            .filter { $0.isCompleted && $0.id != set.id }

        let prevMaxWeight = historicalSets.map(\.weight).max() ?? 0
        let prevMaxVolume = historicalSets.map { $0.weight * Double($0.reps) }.max() ?? 0

        let currentVolume = set.weight * Double(set.reps)

        var types: [PRType] = []
        var newWeight: Double?
        var newVolume: Double?

        if set.weight > prevMaxWeight {
            types.append(.weight)
            newWeight = set.weight
        }

        if currentVolume > prevMaxVolume {
            types.append(.volume)
            newVolume = currentVolume
        }

        return types.isEmpty ? nil : PRResult(
            types: types,
            newMaxWeight: newWeight,
            newMaxVolume: newVolume
        )
    }

    static func bestWeight(for exercise: Exercise, in context: ModelContext) -> Double? {
        let exerciseID = exercise.id
        let predicate = #Predicate<WorkoutExercise> { $0.exercise.id == exerciseID }
        let descriptor = FetchDescriptor(predicate: predicate)

        guard let allWE = try? context.fetch(descriptor) else { return nil }

        let max = allWE
            .flatMap(\.workoutSets)
            .filter(\.isCompleted)
            .map(\.weight)
            .max()

        return max
    }

    static func prDetail(for exercise: Exercise, in context: ModelContext) -> PRDetailInfo? {
        let exerciseID = exercise.id
        let predicate = #Predicate<WorkoutExercise> { $0.exercise.id == exerciseID }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let allWE = try? context.fetch(descriptor) else { return nil }

        let completedPairs: [(set: WorkoutSet, workout: Workout?)] = allWE.flatMap { we in
            we.workoutSets.filter(\.isCompleted).map { (set: $0, workout: we.workout) }
        }
        guard !completedPairs.isEmpty else { return nil }

        guard let bestWeightPair = completedPairs.max(by: { $0.set.weight < $1.set.weight }) else { return nil }
        let bestVolumePair = completedPairs.max(by: {
            $0.set.weight * Double($0.set.reps) < $1.set.weight * Double($1.set.reps)
        })!

        let workoutsWithExercise = Set(allWE.compactMap { $0.workout?.id })

        var historyMap: [Date: Double] = [:]
        for we in allWE {
            guard let wDate = we.workout?.date else { continue }
            let dayMax = we.workoutSets.filter(\.isCompleted).map(\.weight).max() ?? 0
            let day = Calendar.current.startOfDay(for: wDate)
            historyMap[day] = max(historyMap[day] ?? 0, dayMax)
        }
        let history = historyMap.map { (date: $0.key, weight: $0.value) }.sorted { $0.date < $1.date }

        return PRDetailInfo(
            id: exercise.id,
            exerciseName: exercise.name,
            bodyPart: exercise.bodyPart,
            bestWeight: bestWeightPair.set.weight,
            bestWeightReps: bestWeightPair.set.reps,
            bestWeightDate: bestWeightPair.workout?.date ?? Date(),
            bestWeightWorkoutName: bestWeightPair.workout?.name ?? "—",
            bestVolume: bestVolumePair.set.weight * Double(bestVolumePair.set.reps),
            bestVolumeWeight: bestVolumePair.set.weight,
            bestVolumeReps: bestVolumePair.set.reps,
            bestVolumeDate: bestVolumePair.workout?.date ?? Date(),
            totalSets: completedPairs.count,
            totalWorkouts: workoutsWithExercise.count,
            weightHistory: history
        )
    }
}
