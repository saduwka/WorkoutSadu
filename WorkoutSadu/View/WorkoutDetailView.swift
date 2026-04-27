import SwiftUI
import SwiftData
import Foundation
import UIKit
import WidgetKit

struct WorkoutDetailView: View {
    @Bindable var workout: Workout
    @Environment(\.modelContext) private var context
    @Query private var profiles: [BodyProfile]
    @State private var shareURL: URL?
    @State private var showTemplateSaved = false
    @State private var showEditTimeSheet = false

    private var dateStr: String {
        let f = DateFormatter(); f.dateStyle = .long; f.timeStyle = .short
        return f.string(from: workout.date)
    }

    private func hasPR(_ we: WorkoutExercise) -> Bool {
        guard we.exercise.bodyPart != BodyPart.cardio.rawValue else { return false }
        let max = we.workoutSets.filter(\.isCompleted).map(\.weight).max() ?? 0
        guard max > 0 else { return false }
        return max >= (PRManager.bestWeight(for: we.exercise, in: context) ?? 0)
    }

    private func saveAsTemplate() {
        let template = WorkoutTemplate(name: workout.name)
        for (i, we) in workout.workoutExercises.enumerated() {
            let completed = we.workoutSets.filter { $0.isCompleted }
            let last = completed.sorted { $0.order < $1.order }.last
            let te = TemplateExercise(
                order: i, exerciseName: we.exercise.name, bodyPart: we.exercise.bodyPart,
                timerSeconds: we.timerSeconds, defaultSets: max(completed.count, we.workoutSets.count),
                defaultReps: last?.reps ?? 10, defaultWeight: last?.weight ?? 0
            )
            template.exercises.append(te)
        }
        context.insert(template)
        showTemplateSaved = true
    }

    private func exportWorkout() {
        guard let data = try? JSONEncoder().encode(WorkoutExport(from: workout)) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(workout.name).json")
        try? data.write(to: url)
        shareURL = url
    }

    var body: some View {
        ZStack { Color(hex: "#0e0e12").ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header card
                    VStack(alignment: .leading, spacing: 10) {
                        Text(workout.name.isEmpty ? "Тренировка" : workout.name)
                            .font(.custom("BebasNeue-Regular", size: 32))
                            .foregroundStyle(Color(hex: "#f0f0f5"))
                        HStack(spacing: 8) {
                            Label(dateStr, systemImage: "calendar")
                            if let dur = workout.durationFormatted {
                                Label(dur, systemImage: "clock")
                                    .foregroundStyle(Color(hex: "#ff5c3a"))
                            }
                            let kcal = CalorieCalculator.burned(workout: workout, profile: profiles.first)
                            if kcal > 0 {
                                Label("\(kcal) ккал", systemImage: "flame.fill")
                                    .foregroundStyle(Color(hex: "#ffb830"))
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                    }
                    .padding(18)
                    .darkCard()

                    // Exercises
                    VStack(spacing: 1) {
                        ForEach(workout.workoutExercises.sorted { $0.order < $1.order }) { we in
                            NavigationLink(destination: ExerciseView(workoutExercise: we)) {
                                exerciseRow(we)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .darkCard()
                }
                .padding(16)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showEditTimeSheet = true } label: {
                        Label("Редактировать время", systemImage: "clock.arrow.circlepath")
                    }
                    Button { saveAsTemplate() } label: {
                        Label("Сохранить шаблон", systemImage: "doc.on.doc")
                    }
                    Button(action: exportWorkout) {
                        Label("Экспорт JSON", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Color(hex: "#ff5c3a"))
                }
            }
        }
        .alert("Шаблон сохранён", isPresented: $showTemplateSaved) {
            Button("OK", role: .cancel) {}
        } message: { Text("'\(workout.name)' добавлен в шаблоны.") }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let url = shareURL { ActivityViewController(activityItems: [url]) }
        }
        .sheet(isPresented: $showEditTimeSheet) {
            EditWorkoutTimeSheet(workout: workout)
        }
        .preferredColorScheme(.dark)
    }

    private func cardioSummaryLines(_ we: WorkoutExercise) -> [String] {
        CardioPresetsLoader.summaryLines(exerciseName: we.exercise.name, values: we.allCardioValues())
    }

    private func exerciseRow(_ we: WorkoutExercise) -> some View {
        HStack(spacing: 12) {
            if we.supersetGroup != nil {
                RoundedRectangle(cornerRadius: 2).fill(Color.purple).frame(width: 3)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(we.exercise.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    if hasPR(we) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#ffb830"))
                    }
                }
                if let note = we.note, !note.isEmpty {
                    Text(note).font(.system(size: 11)).foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
            Spacer()
            if we.exercise.bodyPart == BodyPart.cardio.rawValue {
                HStack(spacing: 6) {
                    ForEach(cardioSummaryLines(we), id: \.self) { line in
                        Text(line)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "#6b6b80"))
            } else {
                let sets = we.workoutSets.sorted { $0.order < $1.order }
                if let last = sets.last(where: { $0.isCompleted }) {
                    Text("\(sets.filter { $0.isCompleted }.count) × \(last.weight, specifier: "%.1f") кг")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                } else {
                    Text("\(sets.count) сетов")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "#6b6b80").opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5).padding(.leading, 16)
        }
    }
}

// MARK: - Edit workout time (для исправления начала/конца, если не нажали «Начать»)

struct EditWorkoutTimeSheet: View {
    @Bindable var workout: Workout
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [BodyProfile]
    @State private var editStartedAt: Date
    @State private var editFinishedAt: Date

    init(workout: Workout) {
        self._workout = Bindable(wrappedValue: workout)
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: workout.date)
        _editStartedAt = State(initialValue: workout.startedAt ?? dayStart)
        _editFinishedAt = State(initialValue: workout.finishedAt ?? workout.date)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("НАЧАЛО ТРЕНИРОВКИ")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                            .tracking(1)
                        DatePicker("", selection: $editStartedAt, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(Color(hex: "#ff5c3a"))
                    }
                    .padding(16)
                    .darkCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("КОНЕЦ ТРЕНИРОВКИ")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                            .tracking(1)
                        DatePicker("", selection: $editFinishedAt, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(Color(hex: "#ff5c3a"))
                    }
                    .padding(16)
                    .darkCard()

                    if editFinishedAt < editStartedAt {
                        Text("Конец должен быть позже начала")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                    }

                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("РЕДАКТИРОВАТЬ ВРЕМЯ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { saveAndDismiss() }
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                        .disabled(editFinishedAt < editStartedAt)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func saveAndDismiss() {
        guard editFinishedAt >= editStartedAt else { return }
        workout.startedAt = editStartedAt
        workout.finishedAt = editFinishedAt

        if let profile = profiles.first, profile.healthKitEnabled {
            let kcal = CalorieCalculator.burned(workout: workout, profile: profile)
            Task { await HealthKitManager.shared.saveWorkout(workout, calories: kcal) }
        }

        try? context.save()
        WidgetDataManager.sync(context: context)
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
