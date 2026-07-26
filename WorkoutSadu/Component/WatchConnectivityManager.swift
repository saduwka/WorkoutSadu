import Foundation
import WatchConnectivity
import SwiftData
import Combine

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    private var modelContext: ModelContext?
    private var currentExerciseID: UUID?
    private var profiles: [BodyProfile] = []
    private var cancellables = Set<AnyCancellable>()
    private var didConfigure = false

    private override init() {
        super.init()
    }

    func configure(context: ModelContext) {
        modelContext = context
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }

        guard !didConfigure else { return }
        didConfigure = true

        TimerManager.shared.$isRunning
            .combineLatest(TimerManager.shared.$isAlerting, TimerManager.shared.$exerciseName)
            .sink { [weak self] _, _, _ in
                Task { @MainActor in self?.republishActiveWorkout() }
            }
            .store(in: &cancellables)
    }

    func updateProfiles(_ profiles: [BodyProfile]) {
        self.profiles = profiles
    }

    func setCurrentExerciseID(_ id: UUID?) {
        currentExerciseID = id
    }

    func publish(workout: Workout?) {
        let snapshot = makeSnapshot(from: workout)
        pushSnapshot(snapshot)
    }

    func republishActiveWorkout() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.finishedAt == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let active = (try? context.fetch(descriptor))?.first
        publish(workout: active)
    }

    // MARK: - Snapshot

    private func makeSnapshot(from workout: Workout?) -> ActiveWorkoutSnapshot? {
        guard let workout, workout.finishedAt == nil, workout.startedAt != nil else { return nil }

        let exercises = workout.workoutExercises
            .sorted { $0.order < $1.order }
            .map { we -> WatchExerciseDTO in
                let sets = we.workoutSets
                    .sorted { $0.order < $1.order }
                    .map { set in
                        WatchSetDTO(
                            id: set.id,
                            order: set.order,
                            reps: set.reps,
                            weight: set.weight,
                            isCompleted: set.isCompleted
                        )
                    }
                return WatchExerciseDTO(
                    id: we.id,
                    name: we.exercise.name,
                    order: we.order,
                    timerSeconds: we.timerSeconds,
                    sets: sets,
                    isCardio: we.exercise.bodyPart == BodyPart.cardio.rawValue
                )
            }

        let timer = TimerManager.shared
        let restEndTime = timer.isRunning ? timer.currentEndDate : nil
        let restExerciseName = (timer.isRunning || timer.isAlerting) ? timer.exerciseName : nil

        return ActiveWorkoutSnapshot(
            workoutID: workout.id,
            workoutName: workout.name,
            startedAt: workout.startedAt,
            currentExerciseID: currentExerciseID ?? exercises.first(where: { !$0.isCardio })?.id,
            exercises: exercises,
            restEndTime: restEndTime,
            restExerciseName: restExerciseName,
            isRestAlerting: timer.isAlerting,
            updatedAt: Date()
        )
    }

    private func pushSnapshot(_ snapshot: ActiveWorkoutSnapshot?) {
        SharedSnapshotStore.save(snapshot)

        guard WCSession.isSupported() else { return }
        let session = WCSession.default

        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            let context: [String: Any] = [
                WatchSyncStorage.contextKey: data,
                "updatedAt": snapshot.updatedAt.timeIntervalSince1970
            ]
            try? session.updateApplicationContext(context)
        } else if session.activationState == .activated {
            try? session.updateApplicationContext([WatchSyncStorage.contextKey: Data()])
        }
    }

    // MARK: - Commands

    private func handle(_ envelope: WatchMessageEnvelope) {
        guard let context = modelContext else { return }

        switch envelope.command {
        case .updateSetValues:
            guard let payload = envelope.setUpdate else { return }
            guard let set = fetchSet(id: payload.setID, in: context) else { return }
            WorkoutSessionActions.updateSetValues(
                set: set,
                weight: payload.weight,
                reps: payload.reps,
                context: context
            )
            republishActiveWorkout()

        case .completeSet:
            guard let payload = envelope.completeSet else { return }
            guard let exercise = fetchExercise(id: payload.exerciseID, in: context),
                  let set = fetchSet(id: payload.setID, in: context)
            else { return }

            WorkoutSessionActions.updateSetValues(
                set: set,
                weight: payload.weight,
                reps: payload.reps,
                context: context
            )
            _ = WorkoutSessionActions.completeSet(
                set: set,
                workoutExercise: exercise,
                context: context
            )
            republishActiveWorkout()

        case .finishWorkout:
            guard let workout = fetchActiveWorkout(in: context) else { return }
            TimerManager.shared.stop()
            WorkoutSessionActions.finishWorkout(workout, context: context, profiles: profiles)
            currentExerciseID = nil
            pushSnapshot(nil)

        case .skipRestTimer:
            TimerManager.shared.stop()
            republishActiveWorkout()

        case .adjustRestTimer:
            guard let payload = envelope.adjustRest else { return }
            TimerManager.shared.adjustRemaining(by: payload.deltaSeconds)
            republishActiveWorkout()

        case .selectExercise:
            guard let payload = envelope.selectExercise else { return }
            currentExerciseID = payload.exerciseID
            republishActiveWorkout()
        }
    }

    private func handleEnvelopeData(_ data: Data) {
        guard let envelope = try? JSONDecoder().decode(WatchMessageEnvelope.self, from: data) else { return }
        handle(envelope)
    }

    private func fetchActiveWorkout(in context: ModelContext) -> Workout? {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.finishedAt == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func fetchSet(id: UUID, in context: ModelContext) -> WorkoutSet? {
        let descriptor = FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    private func fetchExercise(id: UUID, in context: ModelContext) -> WorkoutExercise? {
        let descriptor = FetchDescriptor<WorkoutExercise>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if activationState == .activated {
                republishActiveWorkout()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["envelope"] as? Data else { return }
        Task { @MainActor in
            handleEnvelopeData(data)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["envelope"] as? Data else { return }
        Task { @MainActor in
            handleEnvelopeData(data)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        // iPhone is the publisher; watch receives via its own delegate.
    }
}
