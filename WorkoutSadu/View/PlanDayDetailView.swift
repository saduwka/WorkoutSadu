import SwiftUI
import SwiftData

struct PlanDayDetailView: View {
    let day: PlanDay
    let manager: MonthPlanManager
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var createdWorkout: Workout?
    
    var body: some View {
        ZStack {
            Color(hex: "#0e0e12").ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    if day.isCompleted {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                            Text("Выполнено")
                        }
                        .font(.headline)
                        .foregroundColor(.green)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    ForEach(day.exercises.sorted(by: { $0.order < $1.order })) { ex in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ex.name)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text(ex.bodyPart)
                                    .font(.caption)
                                    .foregroundColor(Color(hex: "#ff5c3a"))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(ex.sets) × \(ex.reps)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                if ex.weight > 0 {
                                    Text("\(String(format: "%.1f", ex.weight)) кг")
                                        .font(.caption)
                                        .foregroundColor(Color(hex: "#6b6b80"))
                                }
                            }
                        }
                        .padding()
                        .darkCard()
                    }
                    
                    if !day.isCompleted {
                        Button {
                            createdWorkout = manager.startWorkoutFromDay(day, context: context)
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Начать тренировку")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(hex: "#ff5c3a"))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.top, 20)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(day.name)
        .sheet(item: $createdWorkout) { workout in
            CreateWorkoutView(workout: workout)
        }
    }
}
