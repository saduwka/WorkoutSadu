import SwiftUI
import WatchConnectivity
import WatchKit
import Combine

@MainActor
final class WatchSessionStore: NSObject, ObservableObject {
    @Published var snapshot: ActiveWorkoutSnapshot?
    @Published var draftWeight: Double = 0
    @Published var draftReps: Int = 10
    @Published var isCompletingSet = false

    private var tickTimer: Timer?
    private var draftDirty = false
    private var draftSetID: UUID?
    private var completingSetID: UUID?

    override init() {
        super.init()
        activateSession()
    }

    deinit {
        tickTimer?.invalidate()
    }

    // MARK: - Session

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func updateTickTimer() {
        let needsTick = snapshot?.isResting == true
        if needsTick {
            guard tickTimer == nil else { return }
            tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.objectWillChange.send()
                    self?.updateTickTimer()
                }
            }
        } else {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    // MARK: - Draft

    private func syncDraftFromSnapshot() {
        guard let set = snapshot?.nextIncompleteSet else { return }
        if draftDirty, draftSetID == set.id { return }
        draftWeight = set.weight
        draftReps = set.reps
        draftSetID = set.id
        draftDirty = false
    }

    func applySnapshot(_ newSnapshot: ActiveWorkoutSnapshot?) {
        if let id = completingSetID,
           let exercise = newSnapshot?.exercises.first(where: { $0.sets.contains(where: { $0.id == id }) }),
           exercise.sets.first(where: { $0.id == id })?.isCompleted == true {
            isCompletingSet = false
            completingSetID = nil
        }

        if newSnapshot == nil {
            isCompletingSet = false
            completingSetID = nil
            draftDirty = false
            draftSetID = nil
        }

        let previousSetID = snapshot?.nextIncompleteSet?.id
        snapshot = newSnapshot
        if newSnapshot?.nextIncompleteSet?.id != previousSetID {
            draftDirty = false
        }
        syncDraftFromSnapshot()
        updateTickTimer()
    }

    // MARK: - Commands

    func send(_ envelope: WatchMessageEnvelope) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        let payload: [String: Any] = ["envelope": data]
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    func updateDraftLocally() {
        guard let set = snapshot?.nextIncompleteSet else { return }
        draftDirty = true
        draftSetID = set.id
        send(WatchMessageEnvelope(
            command: .updateSetValues,
            setUpdate: WatchSetUpdatePayload(setID: set.id, weight: draftWeight, reps: draftReps)
        ))
    }

    func completeCurrentSet() {
        guard !isCompletingSet else { return }
        guard var snap = snapshot,
              let exercise = snap.currentExercise,
              let set = snap.nextIncompleteSet,
              let exerciseIndex = snap.exercises.firstIndex(where: { $0.id == exercise.id }),
              let setIndex = snap.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == set.id })
        else { return }

        isCompletingSet = true
        completingSetID = set.id
        let trackedSetID = set.id

        snap.exercises[exerciseIndex].sets[setIndex].weight = draftWeight
        snap.exercises[exerciseIndex].sets[setIndex].reps = draftReps
        snap.exercises[exerciseIndex].sets[setIndex].isCompleted = true

        if let seconds = snap.exercises[exerciseIndex].timerSeconds, seconds > 0 {
            snap.restEndTime = Date().addingTimeInterval(TimeInterval(seconds))
            snap.restExerciseName = snap.exercises[exerciseIndex].name
            snap.isRestAlerting = false
        }

        draftDirty = false
        snapshot = snap
        syncDraftFromSnapshot()
        updateTickTimer()

        send(WatchMessageEnvelope(
            command: .completeSet,
            completeSet: WatchCompleteSetPayload(
                setID: set.id,
                exerciseID: exercise.id,
                weight: draftWeight,
                reps: draftReps
            )
        ))
        WKInterfaceDevice.current().play(.click)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if completingSetID == trackedSetID {
                isCompletingSet = false
                completingSetID = nil
            }
        }
    }

    func skipRestTimer() {
        clearRestLocally()
        send(WatchMessageEnvelope(command: .skipRestTimer))
    }

    func adjustRestTimer(by deltaSeconds: Int) {
        if var snap = snapshot, let end = snap.restEndTime {
            let newEnd = end.addingTimeInterval(TimeInterval(deltaSeconds))
            if newEnd <= Date() {
                snap.restEndTime = nil
                snap.isRestAlerting = false
            } else {
                snap.restEndTime = newEnd
                snap.isRestAlerting = false
            }
            snapshot = snap
            updateTickTimer()
        }
        send(WatchMessageEnvelope(
            command: .adjustRestTimer,
            adjustRest: WatchAdjustRestPayload(deltaSeconds: deltaSeconds)
        ))
    }

    func finishWorkout() {
        applySnapshot(nil)
        send(WatchMessageEnvelope(command: .finishWorkout))
    }

    func selectExercise(_ id: UUID) {
        if var snap = snapshot {
            snap.currentExerciseID = id
            snapshot = snap
            draftDirty = false
            syncDraftFromSnapshot()
        }
        send(WatchMessageEnvelope(
            command: .selectExercise,
            selectExercise: WatchSelectExercisePayload(exerciseID: id)
        ))
    }

    func adjustWeight(by delta: Double) {
        let next = min(max(draftWeight + delta, -999), 999)
        draftWeight = next
        updateDraftLocally()
    }

    func adjustReps(by delta: Int) {
        let next = min(max(draftReps + delta, 1), 999)
        draftReps = next
        updateDraftLocally()
    }

    // MARK: - Helpers

    private func clearRestLocally() {
        guard var snap = snapshot else { return }
        snap.restEndTime = nil
        snap.restExerciseName = nil
        snap.isRestAlerting = false
        snapshot = snap
        updateTickTimer()
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        if let data = session.receivedApplicationContext[WatchSyncStorage.contextKey] as? Data,
           !data.isEmpty,
           let snapshot = try? JSONDecoder().decode(ActiveWorkoutSnapshot.self, from: data) {
            Task { @MainActor in applySnapshot(snapshot) }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext[WatchSyncStorage.contextKey] as? Data else {
            Task { @MainActor in applySnapshot(nil) }
            return
        }
        if data.isEmpty {
            Task { @MainActor in applySnapshot(nil) }
            return
        }
        guard let snapshot = try? JSONDecoder().decode(ActiveWorkoutSnapshot.self, from: data) else { return }
        Task { @MainActor in
            applySnapshot(snapshot)
        }
    }
}
