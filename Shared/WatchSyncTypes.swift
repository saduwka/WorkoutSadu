import Foundation

// MARK: - Snapshot DTO

struct WatchSetDTO: Codable, Equatable, Identifiable {
    var id: UUID
    var order: Int
    var reps: Int
    var weight: Double
    var isCompleted: Bool
}

struct WatchExerciseDTO: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var order: Int
    var timerSeconds: Int?
    var sets: [WatchSetDTO]
    var isCardio: Bool
}

struct ActiveWorkoutSnapshot: Codable, Equatable {
    var workoutID: UUID
    var workoutName: String
    var startedAt: Date?
    var currentExerciseID: UUID?
    var exercises: [WatchExerciseDTO]
    var restEndTime: Date?
    var restExerciseName: String?
    var isRestAlerting: Bool
    var updatedAt: Date

    var currentExercise: WatchExerciseDTO? {
        guard let id = currentExerciseID else { return exercises.first }
        return exercises.first { $0.id == id } ?? exercises.first
    }

    var nextIncompleteSet: WatchSetDTO? {
        guard let exercise = currentExercise else { return nil }
        return exercise.sets.sorted { $0.order < $1.order }.first { !$0.isCompleted }
    }

    var isResting: Bool {
        guard let end = restEndTime else { return false }
        return end > Date()
    }

    init(
        workoutID: UUID,
        workoutName: String,
        startedAt: Date?,
        currentExerciseID: UUID?,
        exercises: [WatchExerciseDTO],
        restEndTime: Date?,
        restExerciseName: String?,
        isRestAlerting: Bool = false,
        updatedAt: Date
    ) {
        self.workoutID = workoutID
        self.workoutName = workoutName
        self.startedAt = startedAt
        self.currentExerciseID = currentExerciseID
        self.exercises = exercises
        self.restEndTime = restEndTime
        self.restExerciseName = restExerciseName
        self.isRestAlerting = isRestAlerting
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workoutID = try c.decode(UUID.self, forKey: .workoutID)
        workoutName = try c.decode(String.self, forKey: .workoutName)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        currentExerciseID = try c.decodeIfPresent(UUID.self, forKey: .currentExerciseID)
        exercises = try c.decode([WatchExerciseDTO].self, forKey: .exercises)
        restEndTime = try c.decodeIfPresent(Date.self, forKey: .restEndTime)
        restExerciseName = try c.decodeIfPresent(String.self, forKey: .restExerciseName)
        isRestAlerting = try c.decodeIfPresent(Bool.self, forKey: .isRestAlerting) ?? false
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Commands

enum WatchCommand: String, Codable {
    case updateSetValues
    case completeSet
    case finishWorkout
    case skipRestTimer
    case adjustRestTimer
    case selectExercise
}

struct WatchSetUpdatePayload: Codable {
    var setID: UUID
    var weight: Double
    var reps: Int
}

struct WatchCompleteSetPayload: Codable {
    var setID: UUID
    var exerciseID: UUID
    var weight: Double
    var reps: Int
}

struct WatchSelectExercisePayload: Codable {
    var exerciseID: UUID
}

struct WatchAdjustRestPayload: Codable {
    var deltaSeconds: Int
}

struct WatchMessageEnvelope: Codable {
    var command: WatchCommand
    var setUpdate: WatchSetUpdatePayload?
    var completeSet: WatchCompleteSetPayload?
    var selectExercise: WatchSelectExercisePayload?
    var adjustRest: WatchAdjustRestPayload?
}

// MARK: - Storage Keys

enum WatchSyncStorage {
    static let appGroupID = "group.com.saduwka.WorkoutSadu"
    static let snapshotKey = "activeWorkoutSnapshot"
    static let contextKey = "activeWorkoutContext"
}
