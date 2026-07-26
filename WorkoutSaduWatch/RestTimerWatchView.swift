import SwiftUI
import WatchKit

struct RestTimerWatchView: View {
    @ObservedObject var store: WatchSessionStore
    let endTime: Date
    let exerciseName: String?

    private var remaining: Int {
        max(0, Int(ceil(endTime.timeIntervalSinceNow)))
    }

    private var progress: Double {
        let configured = store.snapshot?.currentExercise?.timerSeconds ?? 0
        let total = max(Double(configured), Double(remaining), 1)
        return min(1, max(0, 1 - Double(remaining) / total))
    }

    private var completedSetNumber: Int {
        guard let exercise = store.snapshot?.currentExercise else { return 0 }
        return exercise.sets.filter(\.isCompleted).count
    }

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)

            Text(completedSetNumber > 0 ? "ПОДХОД \(completedSetNumber) · ОТДЫХ" : "ОТДЫХ")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WatchTheme.textMuted)
                .tracking(1)

            if let exerciseName, !exerciseName.isEmpty {
                Text(exerciseName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(WatchTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text(timeString(remaining))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .monospacedDigit()
            }
            .frame(width: 108, height: 108)

            HStack(spacing: 18) {
                circleButton(systemName: "minus") {
                    store.adjustRestTimer(by: -15)
                }
                circleButton(systemName: "plus") {
                    store.adjustRestTimer(by: 15)
                }
            }

            WatchPrimaryButton(title: "Пропустить") {
                store.skipRestTimer()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatchTheme.bg)
    }

    private func circleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WatchTheme.textPrimary)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
