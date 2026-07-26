import Foundation

enum SharedSnapshotStore {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: WatchSyncStorage.appGroupID)
    }

    static func save(_ snapshot: ActiveWorkoutSnapshot?) {
        guard let defaults else { return }
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: WatchSyncStorage.snapshotKey)
        } else {
            defaults.removeObject(forKey: WatchSyncStorage.snapshotKey)
        }
    }

    static func load() -> ActiveWorkoutSnapshot? {
        guard let defaults,
              let data = defaults.data(forKey: WatchSyncStorage.snapshotKey),
              let snapshot = try? JSONDecoder().decode(ActiveWorkoutSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }
}
