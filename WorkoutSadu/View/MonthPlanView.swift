import SwiftUI
import SwiftData

struct MonthPlanView: View {
    @Environment(\.modelContext) private var context
    @State private var manager = MonthPlanManager()
    
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @Query private var profiles: [BodyProfile]
    
    var body: some View {
        ZStack {
            Color(hex: "#0e0e12").ignoresSafeArea()
            
            if manager.isGenerating {
                VStack(spacing: 20) {
                    ProgressView()
                        .tint(Color(hex: "#ff5c3a"))
                        .scaleEffect(1.5)
                    Text(manager.progressMessage)
                        .foregroundColor(.white.opacity(0.8))
                }
            } else if let plan = manager.activePlan {
                planContent(plan)
            } else {
                emptyState
            }
        }
        .onAppear { manager.loadActive(context: context) }
        .alert("Ошибка", isPresented: .init(get: { manager.errorMessage != nil }, set: { _ in manager.errorMessage = nil })) {
            Button("ОК", role: .cancel) {}
        } message: {
            Text(manager.errorMessage ?? "")
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(Color(hex: "#ff5c3a"))
            
            VStack(spacing: 8) {
                Text("Персональная программа")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text("Gemini проанализирует твой прогресс за месяц и создаст идеальный план на следующие 4 недели.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(hex: "#6b6b80"))
                    .padding(.horizontal, 40)
            }
            
            Button {
                Task {
                    await manager.generate(workouts: workouts, profile: profiles.first, context: context)
                }
            } label: {
                Text("Сгенерировать план")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(hex: "#ff5c3a"))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 40)
        }
    }
    
    private func planContent(_ plan: MonthPlan) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Анализ AI")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Text(plan.generatedAt, style: .date)
                            .font(.caption)
                            .foregroundColor(Color(hex: "#6b6b80"))
                    }
                    Text(plan.aiSummary)
                        .font(.subheadline)
                        .foregroundColor(Color(hex: "#f0f0f5"))
                }
                .padding()
                .darkCard()
                
                // Weeks
                ForEach(plan.weeks.sorted(by: { $0.weekNumber < $1.weekNumber })) { week in
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Неделя \(week.weekNumber) — \(week.focus)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(hex: "#ff5c3a"))
                            .padding(.horizontal)
                        
                        ForEach(week.days.sorted(by: { $0.dayOfWeek < $1.dayOfWeek })) { day in
                            if day.isRestDay {
                                dayRow(day)
                            } else {
                                NavigationLink(destination: PlanDayDetailView(day: day, manager: manager)) {
                                    dayRow(day)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                
                Button("Пересоздать план") {
                    Task {
                        await manager.generate(workouts: workouts, profile: profiles.first, context: context)
                    }
                }
                .font(.footnote)
                .foregroundColor(Color(hex: "#6b6b80"))
                .padding(.vertical)
            }
            .padding()
        }
    }
    
    private func dayRow(_ day: PlanDay) -> some View {
        HStack(spacing: 12) {
            Text(dayIcon(day))
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(day.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                
                if !day.isRestDay {
                    Text(day.exercises.sorted(by: { $0.order < $1.order }).prefix(3).map { $0.name }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(Color(hex: "#6b6b80"))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if day.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if !day.isRestDay {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color(hex: "#6b6b80"))
            }
        }
        .padding()
        .darkCard()
    }
    
    private func dayIcon(_ day: PlanDay) -> String {
        day.isRestDay ? "🛌" : "💪"
    }
}
