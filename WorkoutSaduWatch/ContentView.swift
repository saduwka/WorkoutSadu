import SwiftUI

struct ContentView: View {
    @StateObject private var store = WatchSessionStore()

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                if snapshot.isResting, let end = snapshot.restEndTime {
                    RestTimerWatchView(
                        store: store,
                        endTime: end,
                        exerciseName: snapshot.restExerciseName
                    )
                } else {
                    ActiveExerciseWatchView(store: store, snapshot: snapshot)
                }
            } else {
                IdleWatchView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
