import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Workout Card

struct WorkoutCardView: View {
    let workout: Workout

    private var dateStr: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: workout.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.name.isEmpty ? "Тренировка" : workout.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    Text(dateStr)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                Spacer()
                if let dur = workout.durationFormatted {
                    Text(dur)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(hex: "#ff5c3a").opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            let exercises = workout.workoutExercises.sorted { $0.order < $1.order }
            if !exercises.isEmpty {
                Text(exercises.prefix(4).map { $0.exercise.name }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .lineLimit(1)
            }

            let totalSets = exercises.flatMap { $0.workoutSets }.filter { $0.isCompleted }.count
            if totalSets > 0 {
                let totalVol = exercises.flatMap { $0.workoutSets }.filter { $0.isCompleted }
                    .reduce(0.0) { $0 + $1.weight * Double($1.reps) }
                HStack(spacing: 14) {
                    statPill(icon: "repeat", value: "\(totalSets) сетов")
                    if totalVol > 0 {
                        statPill(icon: "scalemass.fill", value: formatVol(totalVol))
                    }
                }
            }
        }
        .padding(16)
        .darkCard()
    }

    private func statPill(icon: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: "#6b6b80"))
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
    }

    private func formatVol(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1f т", v / 1000) : String(format: "%.0f кг", v)
    }
}

// MARK: - Workout List

struct WorkoutListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @State private var activeWorkout: Workout?
    @State private var showImporter = false
    @State private var importError: String?
    @State private var showImportError = false

    @Binding var externalWorkout: Workout?
    @Binding var showExternalWorkout: Bool

    init(
        externalWorkout: Binding<Workout?> = .constant(nil),
        showExternalWorkout: Binding<Bool> = .constant(false)
    ) {
        self._externalWorkout = externalWorkout
        self._showExternalWorkout = showExternalWorkout
    }

    private var inProgress: [Workout] { workouts.filter { $0.finishedAt == nil } }
    private var finished:   [Workout] { workouts.filter { $0.finishedAt != nil } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 10) {
                        if !inProgress.isEmpty {
                            sectionHeader("В процессе", icon: "flame.fill", color: Color(hex: "#ff5c3a"))
                            ForEach(inProgress) { workout in
                    Button {
                        activeWorkout = workout
                    } label: {
                                    WorkoutCardView(workout: workout)
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: "flame.fill")
                                                .foregroundStyle(Color(hex: "#ff5c3a"))
                                                .padding(12)
                                        }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { context.delete(workout) } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                            }
                        }

                        if !finished.isEmpty {
                            sectionHeader("Тренировки", icon: "checkmark.circle.fill", color: Color(hex: "#3aff9e"))
                            ForEach(finished) { workout in
                                NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                                    WorkoutCardView(workout: workout)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { context.delete(workout) } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                            }
                        }

                        if workouts.isEmpty {
                            emptyState
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("ТРЕНИРОВКИ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showImporter = true } label: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(Color(hex: "#6b6b80"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let w = Workout(name: "", date: Date())
                        context.insert(w)
                        activeWorkout = w
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                            .fontWeight(.semibold)
                    }
                }
            }
            .fullScreenCover(item: $activeWorkout) { workout in
                CreateWorkoutView(workout: workout)
            }
            .onChange(of: showExternalWorkout) { _, show in
                if show, let w = externalWorkout {
                    externalWorkout = nil
                    showExternalWorkout = false
                    activeWorkout = w
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType.json], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    for url in urls {
                        guard url.startAccessingSecurityScopedResource() else { continue }
                        defer { url.stopAccessingSecurityScopedResource() }
                        try? WorkoutImporter.importJSON(from: url, into: context)
                    }
                }
            }
            .alert("Ошибка импорта", isPresented: $showImportError) {
                Button("OK", role: .cancel) {}
            } message: { Text(importError ?? "") }
        }
        .preferredColorScheme(.dark)
    }

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)
            Spacer()
        }
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: "#6b6b80"))
            Text("Нет тренировок")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: "#f0f0f5"))
            Text("Нажми + чтобы начать")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
