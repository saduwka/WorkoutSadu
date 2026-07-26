import Foundation
import SwiftData

enum WorkoutSessionActions {
    // MARK: - Set Updates

    static func updateSetValues(set: WorkoutSet, weight: Double, reps: Int, context: ModelContext) {
        let clampedWeight = min(max(weight, -999), 999)
        let clampedReps = min(max(reps, 1), 999)
        set.weight = clampedWeight
        set.reps = clampedReps
        try? context.save()
    }

    // MARK: - Complete Set

    @discardableResult
    static func completeSet(
        set: WorkoutSet,
        workoutExercise: WorkoutExercise,
        context: ModelContext,
        timerManager: TimerManager = .shared
    ) -> PRResult? {
        guard !set.isCompleted else { return nil }

        set.isCompleted = true
        set.completedAt = Date()

        if let workout = workoutExercise.workout, workout.startedAt == nil {
            workout.startedAt = set.completedAt
        }

        let pr = PRManager.check(set: set, exercise: workoutExercise.exercise, in: context)

        if let seconds = workoutExercise.timerSeconds, seconds > 0 {
            timerManager.start(
                seconds: seconds,
                exerciseID: workoutExercise.id.uuidString,
                exerciseName: workoutExercise.exercise.name
            )
        }

        let sortedSets = workoutExercise.workoutSets.sorted { $0.order < $1.order }
        if sortedSets.last?.id == set.id {
            let next = WorkoutSet(order: set.order + 1, reps: set.reps, weight: set.weight)
            context.insert(next)
            workoutExercise.workoutSets.append(next)
        }

        try? context.save()
        return pr
    }

    // MARK: - Finish Workout

    static func finishWorkout(
        _ workout: Workout,
        context: ModelContext,
        profiles: [BodyProfile],
        healthKit: HealthKitManager = .shared,
        timerManager: TimerManager = .shared
    ) {
        guard workout.finishedAt == nil else { return }

        timerManager.stop()
        workout.date = workout.startedAt ?? Date()
        workout.finishedAt = Date()
        try? context.save()

        if let profile = profiles.first, profile.healthKitEnabled {
            let kcal = CalorieCalculator.burned(workout: workout, profile: profile)
            Task { await healthKit.saveWorkout(workout, calories: kcal) }
        }
    }
}
