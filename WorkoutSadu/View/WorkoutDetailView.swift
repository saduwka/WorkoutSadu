import SwiftUI
import SwiftData
import Foundation
import UIKit

struct WorkoutDetailView: View {
    @Bindable var workout: Workout
    @Environment(\.modelContext) private var context
    @Query private var profiles: [BodyProfile]
    @State private var shareURL: URL?
    @State private var showTemplateSaved = false

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
        .preferredColorScheme(.dark)
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
                    if let d = we.distance { Text(String(format: "%.1f км", d)) }
                    if let t = we.cardioTimeSeconds { Text("\(t/60) мин") }
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

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
