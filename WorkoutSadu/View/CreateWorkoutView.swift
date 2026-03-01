import SwiftUI
import SwiftData
import UserNotifications
import WidgetKit

struct CreateWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var workout: Workout
    @State private var showExercisePicker = false
    @State private var showDiscardAlert = false
    @State private var name: String
    @State private var elapsedSeconds = 0
    @State private var elapsedTimer: Timer?
    @State private var workoutStarted = false

    init(workout: Workout) {
        self._workout = Bindable(wrappedValue: workout)
        self._name = State(initialValue: workout.name)
    }

    private var sortedExercises: [WorkoutExercise] {
        workout.workoutExercises.sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        // Timer / Start
                        if workoutStarted {
                            HStack {
                                Image(systemName: "clock").foregroundStyle(Color(hex: "#6b6b80"))
                                Text(formatElapsed(elapsedSeconds))
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(Color(hex: "#ff5c3a"))
                                Spacer()
                            }
                            .padding(16)
                            .darkCard()
                        } else {
                            Button {
                                workout.startedAt = Date()
                                workoutStarted = true
                                startElapsedTimer()
                            } label: {
                                HStack {
                                    Spacer()
                                    Label("Начать тренировку", systemImage: "play.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(Color(hex: "#ff5c3a"))
                                    Spacer()
                                }
                                .padding(16)
                                .darkCard(accentBorder: Color(hex: "#ff5c3a").opacity(0.4))
                            }
                            .buttonStyle(.plain)
                        }

                        // Name field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("НАЗВАНИЕ")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .tracking(1)
                            TextField("Новая тренировка", text: $name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(hex: "#f0f0f5"))
                        }
                        .padding(16)
                        .darkCard()

                        // Exercises
                        VStack(spacing: 0) {
                            HStack {
                                Text("УПРАЖНЕНИЯ")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(hex: "#6b6b80"))
                                    .tracking(1)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 8)

                            ForEach(sortedExercises) { we in
                                NavigationLink(destination: ExerciseView(workoutExercise: we)) {
                                    exerciseRow(we)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading) {
                                    if we.supersetGroup != nil {
                                        Button { removeSupersetLink(we) } label: {
                                            Label("Отвязать", systemImage: "link.badge.plus")
                                        }.tint(.gray)
                                    } else {
                                        Button { linkSuperset(we) } label: {
                                            Label("Суперсет", systemImage: "link")
                                        }.tint(.purple)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { context.delete(we) } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                            }

                            Button {
                                showExercisePicker = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Color(hex: "#ff5c3a"))
                                    Text("Добавить упражнение")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Color(hex: "#ff5c3a"))
                                    Spacer()
                                }
                                .padding(16)
                            }
                        }
                        .darkCard()
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(name.isEmpty ? "Новая тренировка" : name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { workout.name = t }
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down").foregroundStyle(Color(hex: "#6b6b80"))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button {
                            let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !t.isEmpty else { return }
                            workout.name = t
                            workout.date = Date()
                            workout.finishedAt = Date()
                            stopElapsedTimer()
                            WidgetDataManager.sync(context: context)
                            WidgetCenter.shared.reloadAllTimelines()
                            dismiss()
                        } label: {
                            Label("Завершить тренировку", systemImage: "checkmark.circle")
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(role: .destructive) { showDiscardAlert = true } label: {
                            Label("Отменить тренировку", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(Color(hex: "#ff5c3a"))
                    }
                }
            }
            .fullScreenCover(isPresented: $showExercisePicker) {
                ExercisePickerView { selected in
                    if !workout.workoutExercises.contains(selected) {
                        selected.order = (workout.workoutExercises.map(\.order).max() ?? -1) + 1
                        workout.workoutExercises.append(selected)
                    }
                    showExercisePicker = false
                }
            }
            .alert("Отменить тренировку?", isPresented: $showDiscardAlert) {
                Button("Отменить", role: .destructive) {
                    stopElapsedTimer()
                    context.delete(workout)
                    dismiss()
                }
                Button("Назад", role: .cancel) {}
            } message: { Text("Все данные будут удалены безвозвратно.") }
            .onAppear {
                if workout.startedAt != nil { workoutStarted = true; startElapsedTimer() }
            }
            .onDisappear { stopElapsedTimer() }
        }
        .preferredColorScheme(.dark)
    }

    private func exerciseRow(_ we: WorkoutExercise) -> some View {
        HStack(spacing: 12) {
            if let group = we.supersetGroup {
                RoundedRectangle(cornerRadius: 2)
                    .fill(supersetColor(group))
                    .frame(width: 4)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(we.exercise.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    if hasPR(we) {
                        Image(systemName: "trophy.fill").font(.caption).foregroundStyle(Color(hex: "#ffb830"))
                    }
                }
                if we.supersetGroup != nil {
                    Text("Суперсет").font(.caption2).foregroundStyle(Color(hex: "#a855f7"))
                }
            }
            Spacer()
            if we.exercise.bodyPart == BodyPart.cardio.rawValue {
                HStack(spacing: 6) {
                    if let d = we.distance { Text(String(format: "%.1f км", d)) }
                    if let t = we.cardioTimeSeconds { Text("\(t/60) мин") }
                }
                .font(.caption).foregroundStyle(Color(hex: "#6b6b80"))
            } else {
                Text(we.completedSetsCount > 0 ? "\(we.completedSetsCount) сетов" : "Нет сетов")
                    .font(.caption).foregroundStyle(Color(hex: "#6b6b80"))
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color(hex: "#6b6b80").opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(Divider().padding(.leading, 16), alignment: .bottom)
    }

    private func hasPR(_ we: WorkoutExercise) -> Bool {
        guard we.exercise.bodyPart != BodyPart.cardio.rawValue else { return false }
        let m = we.workoutSets.filter(\.isCompleted).map(\.weight).max() ?? 0
        guard m > 0 else { return false }
        return m >= (PRManager.bestWeight(for: we.exercise, in: context) ?? 0)
    }

    private func startElapsedTimer() {
        updateElapsed()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in updateElapsed() }
    }
    private func stopElapsedTimer() { elapsedTimer?.invalidate(); elapsedTimer = nil }
    private func updateElapsed() {
        guard let s = workout.startedAt else { return }
        elapsedSeconds = Int(Date().timeIntervalSince(s))
    }
    private func formatElapsed(_ t: Int) -> String {
        let h = t/3600, m = (t%3600)/60, s = t%60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private func linkSuperset(_ we: WorkoutExercise) {
        let sorted = sortedExercises
        guard let idx = sorted.firstIndex(where: { $0.id == we.id }), idx + 1 < sorted.count else { return }
        let next = sorted[idx + 1]
        let group = we.supersetGroup ?? next.supersetGroup ?? ((sorted.compactMap(\.supersetGroup).max() ?? 0) + 1)
        we.supersetGroup = group; next.supersetGroup = group
    }
    private func removeSupersetLink(_ we: WorkoutExercise) {
        guard let group = we.supersetGroup else { return }
        we.supersetGroup = nil
        let remaining = workout.workoutExercises.filter { $0.supersetGroup == group }
        if remaining.count < 2 { remaining.forEach { $0.supersetGroup = nil } }
    }
    private func supersetColor(_ group: Int) -> Color {
        [Color.purple, .cyan, .pink, .indigo, .mint, .teal][abs(group) % 6]
    }
}
