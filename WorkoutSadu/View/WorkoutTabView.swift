import SwiftUI
import SwiftData

struct HealthTabView: View {
    @State private var section: Int = 0
    @State private var workoutFromTemplate: Workout?
    @State private var showCreateFromTemplate = false

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker

            Group {
                switch section {
                case 0:
                    WorkoutListView(
                        externalWorkout: $workoutFromTemplate,
                        showExternalWorkout: $showCreateFromTemplate
                    )
                case 1:
                    TemplateListView(onStartWorkout: { workout in
                        workoutFromTemplate = workout
                        showCreateFromTemplate = true
                        section = 0
                    })
                case 2:
                    StatsView()
                case 3:
                    FoodView()
                case 4:
                    MonthPlanView()
                default:
                    WorkoutListView(
                        externalWorkout: $workoutFromTemplate,
                        showExternalWorkout: $showCreateFromTemplate
                    )
                }
            }
        }
        .background(Color(hex: "#0e0e12"))
    }

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            let tabs = [
                ("Трен.", "dumbbell.fill"),
                ("Шаблоны", "doc.on.doc"),
                ("Прогресс", "chart.line.uptrend.xyaxis"),
                ("Еда", "fork.knife"),
                ("План", "calendar")
            ]

            ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { section = i }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.1)
                            .font(.system(size: 14))
                        Text(tab.0)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(section == i ? Color(hex: "#ff5c3a") : Color(hex: "#6b6b80"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .background(Color(hex: "#0e0e12"))
    }
}
