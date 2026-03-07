import SwiftUI
import SwiftData

struct ExerciseEditView: View {
    @Bindable var workoutExercise: WorkoutExercise
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedBodyPart: BodyPart = .chest
    @State private var timerMinutes = 0; @State private var timerSeconds = 0
    @State private var showGifSearch = false
    @State private var gifPreviewData: Data?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                Form {
                    Section("Упражнение") {
                        TextField("Название", text: $name).foregroundStyle(Color(hex: "#f0f0f5"))
                        Picker("Группа мышц", selection: $selectedBodyPart) {
                            ForEach(BodyPart.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    }
                    if selectedBodyPart != .cardio {
                        Section {
                            HStack(spacing: 0) {
                                Picker("Мин", selection: $timerMinutes) {
                                    ForEach(0...10, id: \.self) { Text("\($0) мин").tag($0) }
                                }
                                .pickerStyle(.wheel).frame(maxWidth: .infinity)
                                Picker("Сек", selection: $timerSeconds) {
                                    ForEach([0,15,30,45], id: \.self) { Text("\($0) сек").tag($0) }
                                }
                                .pickerStyle(.wheel).frame(maxWidth: .infinity)
                            }
                            .frame(height: 120)
                        } header: { Text("Таймер отдыха") }
                        footer: { Text("Запускается после каждого сета") }
                    }

                    Section("GIF-демонстрация") {
                        if let data = gifPreviewData {
                            AnimatedGifView(data: data)
                                .frame(height: 160)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .listRowBackground(Color(hex: "#16161d"))
                        }

                        if workoutExercise.exercise.gifURL != nil {
                            Button(role: .destructive) {
                                if let url = workoutExercise.exercise.gifURL {
                                    ExerciseGifManager.shared.removeGif(for: url)
                                }
                                workoutExercise.exercise.gifURL = nil
                                gifPreviewData = nil
                            } label: {
                                Label("Удалить GIF", systemImage: "trash")
                                    .foregroundStyle(Color(hex: "#ff5c3a"))
                            }
                        }

                        Button { showGifSearch = true } label: {
                            Label(
                                workoutExercise.exercise.gifURL != nil ? "Заменить GIF" : "Найти GIF",
                                systemImage: "magnifyingglass"
                            )
                            .foregroundStyle(Color(hex: "#4a8cff"))
                        }
                    }
                }
                .dismissKeyboardOnTap()
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.foregroundStyle(Color(hex: "#6b6b80"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { workoutExercise.exercise.name = t }
                        workoutExercise.exercise.bodyPart = selectedBodyPart.rawValue
                        let total = timerMinutes * 60 + timerSeconds
                        workoutExercise.timerSeconds = total > 0 ? total : nil
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(Color(hex: "#ff5c3a")).fontWeight(.bold)
                }
            }
            .onAppear {
                name = workoutExercise.exercise.name
                selectedBodyPart = BodyPart(rawValue: workoutExercise.exercise.bodyPart) ?? .chest
                let total = workoutExercise.timerSeconds ?? 0
                timerMinutes = total / 60
                let raw = total % 60
                timerSeconds = [0,15,30,45].min(by: { abs($0-raw) < abs($1-raw) }) ?? 0
            }
            .task {
                if let url = workoutExercise.exercise.gifURL, !url.isEmpty {
                    gifPreviewData = await ExerciseGifManager.shared.loadGif(from: url)
                }
            }
            .sheet(isPresented: $showGifSearch) {
                GifSearchSheet(initialQuery: workoutExercise.exercise.name) { url in
                    workoutExercise.exercise.gifURL = url
                    Task { gifPreviewData = await ExerciseGifManager.shared.loadGif(from: url) }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
