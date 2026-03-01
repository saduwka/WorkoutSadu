import SwiftUI
import SwiftData

struct MeTabView: View {
    @State private var section: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker

            Group {
                switch section {
                case 0:  BodyProfileView()
                case 1:  MeQuestsView()
                case 2:  MeRecordsView()
                default: BodyProfileView()
                }
            }
        }
        .background(Color(hex: "#0e0e12"))
    }

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            let tabs = [
                ("Профиль", "person.fill"),
                ("Квесты", "trophy.fill"),
                ("Рекорды", "medal.fill")
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

// MARK: - Quests

struct MeQuestsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \GeneratedQuest.order) private var allQuests: [GeneratedQuest]
    @Query(sort: \Workout.date) private var workouts: [Workout]
    @Query private var profiles: [BodyProfile]
    @State private var questsLoading = false

    private var activeQuests: [GeneratedQuest] { allQuests.filter { !$0.isCompleted } }
    private var completedQuests: [GeneratedQuest] { allQuests.filter { $0.isCompleted } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        if allQuests.isEmpty {
                            emptyState
                        } else {
                            if !activeQuests.isEmpty {
                                sectionLabel("АКТИВНЫЕ")
                                ForEach(activeQuests) { quest in
                                    questCard(quest)
                                }
                            }
                            if !completedQuests.isEmpty {
                                sectionLabel("ЗАВЕРШЁННЫЕ")
                                ForEach(completedQuests.prefix(10)) { quest in
                                    questCard(quest)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("КВЕСТЫ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await generateQuests() }
                    } label: {
                        if questsLoading {
                            ProgressView().tint(Color(hex: "#ff5c3a"))
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Color(hex: "#ff5c3a"))
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color(hex: "#ffb830"))
            Text("Нет квестов")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(hex: "#f0f0f5"))
            Text("Нажмите обновить, чтобы AI сгенерировал квесты")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .darkCard()
    }

    private func questCard(_ quest: GeneratedQuest) -> some View {
        HStack(spacing: 12) {
            Image(systemName: quest.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(quest.isCompleted ? Color(hex: "#3aff9e") : Color(hex: "#6b6b80"))

            VStack(alignment: .leading, spacing: 4) {
                Text(quest.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(quest.isCompleted ? Color(hex: "#6b6b80") : Color(hex: "#f0f0f5"))
                    .strikethrough(quest.isCompleted)
                if !quest.subtitle.isEmpty {
                    Text(quest.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                        .lineLimit(2)
                }
            }

            Spacer()

            if !quest.isCompleted {
                Button {
                    quest.isCompleted = true
                    try? context.save()
                } label: {
                    Text("Готово")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color(hex: "#3aff9e"))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .darkCard()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(hex: "#6b6b80"))
            .tracking(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func generateQuests() async {
        questsLoading = true
        await GamificationManager.generateQuests(workouts: workouts, profile: profiles.first, context: context)
        questsLoading = false
    }
}

// MARK: - Records

struct MeRecordsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.date) private var workouts: [Workout]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        personalRecordsSection
                        achievementsSection
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("РЕКОРДЫ")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private var personalRecordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ЛИЧНЫЕ РЕКОРДЫ")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)

            let prs = exercises.compactMap { ex -> (String, Double)? in
                guard let w = PRManager.bestWeight(for: ex, in: context), w > 0 else { return nil }
                return (ex.name, w)
            }.sorted { $0.1 > $1.1 }

            if prs.isEmpty {
                Text("Завершите тренировки, чтобы увидеть рекорды")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                ForEach(Array(prs.prefix(15).enumerated()), id: \.offset) { _, pr in
                    HStack {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#ffb830"))
                        Text(pr.0)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: "#f0f0f5"))
                        Spacer()
                        Text("\(String(format: "%.1f", pr.1)) кг")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(hex: "#ffb830"))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .darkCard()
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ДОСТИЖЕНИЯ")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)

            let finishedWorkouts = workouts.filter { $0.finishedAt != nil }
            let allSets = finishedWorkouts.flatMap { $0.workoutExercises }.flatMap { $0.workoutSets }
            let totalSets = allSets.count
            let totalVolume = allSets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
            let uniqueExercises = Set(finishedWorkouts.flatMap { $0.workoutExercises }.map { $0.exercise.name }).count

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                achievementCard("Тренировок", "\(finishedWorkouts.count)", "figure.run", Color(hex: "#ff5c3a"))
                achievementCard("Сетов", "\(totalSets)", "repeat", Color(hex: "#5b8cff"))
                achievementCard("Объём", "\(Int(totalVolume / 1000))т", "scalemass.fill", Color(hex: "#ffb830"))
                achievementCard("Упражнений", "\(uniqueExercises)", "list.bullet", Color(hex: "#3aff9e"))
            }
        }
        .padding(14)
        .darkCard()
    }

    private func achievementCard(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: "#f0f0f5"))
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
