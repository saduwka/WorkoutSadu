import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - Data

struct WidgetMuscle {
    let name: String
    let emoji: String
    let daysAgo: Int      // -1 = never
    let state: String     // "done", "warning", "missed"

    var stateColor: Color {
        switch state {
        case "done":    return Color(hex: "#3aff9e")
        case "warning": return Color(hex: "#ffb830")
        default:        return Color(hex: "#ff5c3a")
        }
    }

    var shortLabel: String {
        if daysAgo < 0 { return "—" }
        if daysAgo == 0 { return "✓" }
        return "\(daysAgo)д"
    }
}

struct WorkoutWidgetData {
    let streak: Int
    let thisWeek: Int
    let weeklyGoal: Int
    let daysSince: Int
    let lastDate: Date?
    let totalWorkouts: Int
    let xp: Int
    let level: Int
    let levelName: String
    let levelEmoji: String
    let prExercise: String
    let prWeight: Double
    let muscles: [WidgetMuscle]
    let weekVolume: Double
    let weekDays: [Int]       // 0=Mon ... 6=Sun

    var urgentMuscle: WidgetMuscle? {
        muscles.first { $0.state == "missed" } ?? muscles.first { $0.state == "warning" }
    }

    static let placeholder = WorkoutWidgetData(
        streak: 3, thisWeek: 2, weeklyGoal: 3, daysSince: 1,
        lastDate: Date(), totalWorkouts: 42, xp: 700,
        level: 3, levelName: "Спортсмен", levelEmoji: "⚡",
        prExercise: "Жим лёжа", prWeight: 80,
        muscles: [
            WidgetMuscle(name: "Ноги", emoji: "🦵", daysAgo: 2, state: "done"),
            WidgetMuscle(name: "Грудь", emoji: "🫁", daysAgo: 5, state: "done"),
            WidgetMuscle(name: "Спина", emoji: "🔙", daysAgo: 8, state: "warning"),
            WidgetMuscle(name: "Руки", emoji: "💪", daysAgo: 12, state: "missed"),
            WidgetMuscle(name: "Плечи", emoji: "🙆", daysAgo: 3, state: "done"),
            WidgetMuscle(name: "Пресс", emoji: "🔥", daysAgo: 1, state: "done"),
        ],
        weekVolume: 12500,
        weekDays: [0, 2, 4]
    )

    static func load() -> WorkoutWidgetData {
        guard let d = UserDefaults(suiteName: "group.com.saduwka.WorkoutSadu") else {
            return .placeholder
        }
        let lastTS = d.double(forKey: "widgetLastDate")

        var muscles: [WidgetMuscle] = []
        if let arr = d.array(forKey: "widgetMuscles") as? [[String: Any]] {
            for item in arr {
                muscles.append(WidgetMuscle(
                    name: item["name"] as? String ?? "",
                    emoji: item["emoji"] as? String ?? "",
                    daysAgo: item["daysAgo"] as? Int ?? -1,
                    state: item["state"] as? String ?? "missed"
                ))
            }
        }

        return WorkoutWidgetData(
            streak: d.integer(forKey: "widgetStreak"),
            thisWeek: d.integer(forKey: "widgetThisWeek"),
            weeklyGoal: max(1, d.integer(forKey: "widgetWeeklyGoal")),
            daysSince: d.integer(forKey: "widgetDaysSince"),
            lastDate: lastTS > 0 ? Date(timeIntervalSince1970: lastTS) : nil,
            totalWorkouts: d.integer(forKey: "widgetTotalWorkouts"),
            xp: d.integer(forKey: "widgetXP"),
            level: d.integer(forKey: "widgetLevel"),
            levelName: d.string(forKey: "widgetLevelName") ?? "Новичок",
            levelEmoji: d.string(forKey: "widgetLevelEmoji") ?? "🌱",
            prExercise: d.string(forKey: "widgetPRExercise") ?? "",
            prWeight: d.double(forKey: "widgetPRWeight"),
            muscles: muscles,
            weekVolume: d.double(forKey: "widgetWeekVolume"),
            weekDays: d.array(forKey: "widgetWeekDays") as? [Int] ?? []
        )
    }
}

// MARK: - Timeline

struct WorkoutEntry: TimelineEntry {
    let date: Date
    let data: WorkoutWidgetData
}

struct WorkoutTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutEntry {
        WorkoutEntry(date: .now, data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutEntry) -> Void) {
        completion(WorkoutEntry(date: .now, data: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutEntry>) -> Void) {
        let entry = WorkoutEntry(date: .now, data: .load())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let data: WorkoutWidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: level + XP
            HStack(spacing: 5) {
                Text(data.levelEmoji).font(.system(size: 14))
                Text("\(data.xp) XP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#ff5c3a"))
                Spacer()
                if data.streak > 0 {
                    Text("🔥\(data.streak)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "#ffb830"))
                }
            }

            Spacer()

            // Days since — the big info
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                if data.daysSince == 0 {
                    Text("✓")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#3aff9e"))
                } else if data.daysSince > 0 {
                    Text("\(data.daysSince)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(daysSinceColor)
                } else {
                    Text("—")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                Text(daysSinceSubtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "#6b6b80"))
            }

            Spacer().frame(height: 6)

            // Week progress bar
            weekProgressBar

            Spacer().frame(height: 8)

            // Urgent muscle hint
            if let urgent = data.urgentMuscle {
                HStack(spacing: 4) {
                    Text(urgent.emoji).font(.system(size: 11))
                    Text(urgent.name)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(urgent.stateColor)
                    Text(urgent.daysAgo > 0 ? "· \(urgent.daysAgo)д" : "")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
        }
        .padding(14)
        .containerBackground(for: .widget) {
            Color(hex: "#111118")
        }
    }

    private var weekProgressBar: some View {
        GeometryReader { geo in
            let progress = min(1.0, Double(data.thisWeek) / Double(data.weeklyGoal))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 6)
                Capsule()
                    .fill(
                        data.thisWeek >= data.weeklyGoal
                        ? Color(hex: "#3aff9e")
                        : Color(hex: "#ff5c3a")
                    )
                    .frame(width: max(6, geo.size.width * progress), height: 6)
            }
        }
        .frame(height: 6)
        .overlay(
            HStack {
                Text("\(data.thisWeek)/\(data.weeklyGoal)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                Spacer()
            }
            .offset(y: 10)
        )
    }

    private var daysSinceSubtitle: String {
        if data.daysSince < 0 { return "нет данных" }
        if data.daysSince == 0 { return "тренировка" }
        if data.daysSince == 1 { return "день отдыха" }
        if data.daysSince < 5 { return "дня отдыха" }
        return "дней отдыха"
    }

    private var daysSinceColor: Color {
        if data.daysSince <= 1 { return Color(hex: "#3aff9e") }
        if data.daysSince <= 3 { return Color(hex: "#ffb830") }
        return Color(hex: "#ff5c3a")
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let data: WorkoutWidgetData

    var body: some View {
        HStack(spacing: 0) {
            // Left: week overview
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(spacing: 5) {
                    Text(data.levelEmoji).font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(data.levelName.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                            .tracking(1)
                        Text("\(data.xp) XP")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                    }
                    Spacer()
                    if data.streak > 0 {
                        HStack(spacing: 2) {
                            Text("🔥")
                                .font(.system(size: 11))
                            Text("\(data.streak) нед")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: "#ffb830"))
                        }
                    }
                }

                Spacer()

                // Week calendar row
                weekCalendarRow

                Spacer().frame(height: 4)

                // Week stats
                HStack(spacing: 10) {
                    miniStat(
                        value: "\(data.thisWeek)/\(data.weeklyGoal)",
                        label: "тренировок",
                        color: data.thisWeek >= data.weeklyGoal ? Color(hex: "#3aff9e") : Color(hex: "#ff5c3a")
                    )
                    if data.weekVolume > 0 {
                        miniStat(
                            value: formatVolume(data.weekVolume),
                            label: "объём",
                            color: Color(hex: "#5b8cff")
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Divider
            Rectangle()
                .fill(Color(hex: "#2a2a35"))
                .frame(width: 1)
                .padding(.vertical, 4)

            // Right: muscle map
            VStack(alignment: .leading, spacing: 4) {
                Text("МЫШЦЫ")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .tracking(1)

                if data.muscles.isEmpty {
                    Spacer()
                    Text("Нет данных")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                    Spacer()
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                        ForEach(Array(data.muscles.prefix(6).enumerated()), id: \.offset) { _, muscle in
                            muscleCell(muscle)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)
        }
        .padding(14)
        .containerBackground(for: .widget) {
            Color(hex: "#111118")
        }
    }

    // Week calendar: Mon-Sun dots
    private var weekCalendarRow: some View {
        let dayLabels = ["П", "В", "С", "Ч", "П", "С", "В"]
        let today = (Calendar.current.component(.weekday, from: Date()) + 5) % 7

        return HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let trained = data.weekDays.contains(i)
                let isToday = i == today
                VStack(spacing: 2) {
                    Text(dayLabels[i])
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(isToday ? Color(hex: "#f0f0f5") : Color(hex: "#6b6b80").opacity(0.6))
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(trained ? Color(hex: "#3aff9e").opacity(0.2) : Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(
                                        isToday ? Color(hex: "#ff5c3a").opacity(0.6) :
                                        trained ? Color(hex: "#3aff9e").opacity(0.3) : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                        if trained {
                            Text("✓")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color(hex: "#3aff9e"))
                        }
                    }
                    .frame(height: 20)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func muscleCell(_ m: WidgetMuscle) -> some View {
        HStack(spacing: 3) {
            Text(m.emoji).font(.system(size: 10))
            VStack(alignment: .leading, spacing: 0) {
                Text(m.name)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
                    .lineLimit(1)
                Text(m.shortLabel)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(m.stateColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(m.stateColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(m.stateColor.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func miniStat(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
    }

    private func formatVolume(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.1fт", v / 1000) }
        return String(format: "%.0fкг", v)
    }
}

// MARK: - Color helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Widget

struct WorkoutSaduWidget: Widget {
    let kind = "WorkoutSaduWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutTimelineProvider()) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Workout Tracker")
        .description("Отдых, прогресс недели и мышцы")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WorkoutEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(data: entry.data)
        default:
            MediumWidgetView(data: entry.data)
        }
    }
}

// MARK: - Bundle

@main
struct WorkoutSaduWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorkoutSaduWidget()
        TimerLiveActivity()
    }
}

// MARK: - Live Activity View

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerAttributes.self) { context in
            LiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                        Text("Отдых")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.endTime.addingTimeInterval(-3600*24)...context.state.endTime, countsDown: true)
                        .monospacedDigit()
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(Color(hex: "#3aff9e"))
                        .frame(width: 80)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let name = context.attributes.exerciseName {
                        Text(name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(Color(hex: "#ff5c3a"))
            } compactTrailing: {
                Text(timerInterval: context.state.endTime.addingTimeInterval(-3600*24)...context.state.endTime, countsDown: true)
                    .monospacedDigit()
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: "#3aff9e"))
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(Color(hex: "#ff5c3a"))
            }
        }
    }
}

struct LiveActivityView: View {
    let context: ActivityViewContext<TimerAttributes>
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                    Text("ОТДЫХ")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                        .tracking(1)
                }
                
                if let name = context.attributes.exerciseName {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                } else {
                    Text("Следующий сет")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 0) {
                Text(timerInterval: context.state.endTime.addingTimeInterval(-3600*24)...context.state.endTime, countsDown: true)
                    .monospacedDigit()
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: "#3aff9e"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(Color(hex: "#0e0e12"))
    }
}

#Preview("Small", as: .systemSmall) {
    WorkoutSaduWidget()
} timeline: {
    WorkoutEntry(date: .now, data: .placeholder)
}

#Preview("Medium", as: .systemMedium) {
    WorkoutSaduWidget()
} timeline: {
    WorkoutEntry(date: .now, data: .placeholder)
}
