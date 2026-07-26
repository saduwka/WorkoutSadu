import WidgetKit
import SwiftUI
import AlarmKit

// MARK: - AlarmKit Live Activity

struct RestAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<RestAlarmMetadata>.self) { context in
            RestAlarmLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                        Text("ОТДЫХ")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                            .tracking(0.8)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestAlarmCountdownText(state: context.state)
                        .monospacedDigit()
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(Color(hex: "#3aff9e"))
                        .frame(minWidth: 64, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let name = context.attributes.metadata?.exerciseName {
                        Text(name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(Color(hex: "#ff5c3a"))
            } compactTrailing: {
                RestAlarmCountdownText(state: context.state)
                    .monospacedDigit()
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#3aff9e"))
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(Color(hex: "#ff5c3a"))
            }
            .keylineTint(Color(hex: "#ff5c3a"))
        }
    }
}

struct RestAlarmLockScreenView: View {
    let context: ActivityViewContext<AlarmAttributes<RestAlarmMetadata>>

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                    Text("ОТДЫХ")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                }

                Text(context.attributes.metadata?.exerciseName ?? "Следующий сет")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            RestAlarmCountdownText(state: context.state)
                .monospacedDigit()
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Color(hex: "#3aff9e"))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular.tint(Color(hex: "#3aff9e").opacity(0.25)), in: .capsule)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        // Без opaque background — система рисует Liquid Glass на Lock Screen.
        .activityBackgroundTint(.clear)
    }
}

struct RestAlarmCountdownText: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let info):
            Text(info.fireDate, style: .timer)
        case .paused(let info):
            let remaining = info.totalCountdownDuration - info.previouslyElapsedDuration
            Text(Duration.seconds(remaining), format: .time(pattern: .minuteSecond))
        case .alert:
            Text("00:00")
        @unknown default:
            Text("--:--")
        }
    }
}

// MARK: - Bundle

@main
struct RestTimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        RestAlarmLiveActivity()
    }
}

// MARK: - Color helper

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
