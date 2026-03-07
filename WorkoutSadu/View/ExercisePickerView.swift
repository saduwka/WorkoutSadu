import SwiftUI
import SwiftData

struct ExercisePickerView: View {
    let onSelect: (WorkoutExercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @State private var searchText = ""
    @State private var filterBodyPart: BodyPart?
    @State private var showCreateNew = false

    private var filtered: [Exercise] {
        var r = allExercises
        if let f = filterBodyPart { r = r.filter { $0.bodyPart == f.rawValue } }
        if !searchText.isEmpty { r = r.filter { $0.name.localizedCaseInsensitiveContains(searchText) } }
        return r
    }
    private var grouped: [(String, [Exercise])] {
        Dictionary(grouping: filtered, by: \.bodyPart).sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                VStack(spacing: 0) {
                    // Body part filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip("Все", selected: filterBodyPart == nil) { filterBodyPart = nil }
                            ForEach(BodyPart.allCases, id: \.self) { part in
                                filterChip(part.rawValue, selected: filterBodyPart == part) {
                                    filterBodyPart = (filterBodyPart == part) ? nil : part
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    }

                    if allExercises.isEmpty {
                        emptyState
                    } else if filtered.isEmpty && !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .background(Color(hex: "#0e0e12"))
                    } else {
                        List {
                            ForEach(grouped, id: \.0) { bodyPart, exs in
                                Section {
                                    ForEach(exs) { ex in
                                        Button { pickExisting(ex) } label: {
                                            HStack {
                                                Text(ex.name)
                                                    .font(.system(size: 15)).foregroundStyle(Color(hex: "#f0f0f5"))
                                                Spacer()
                                                Image(systemName: "plus.circle")
                                                    .foregroundStyle(Color(hex: "#ff5c3a"))
                                            }
                                        }
                                    }
                                } header: {
                                    Text(bodyPart).foregroundStyle(Color(hex: "#6b6b80"))
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Поиск упражнений")
            .navigationTitle("Добавить упражнение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.foregroundStyle(Color(hex: "#6b6b80"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreateNew = true } label: {
                        Image(systemName: "plus").foregroundStyle(Color(hex: "#ff5c3a")).fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showCreateNew) {
                NewExerciseSheet { we in onSelect(we); dismiss() }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? .black : Color(hex: "#6b6b80"))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(selected ? Color(hex: "#ff5c3a") : Color(hex: "#1e1e28"))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 48)).foregroundStyle(Color(hex: "#6b6b80"))
            Text("Нет упражнений").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color(hex: "#f0f0f5"))
            Text("Нажми + чтобы создать первое").font(.system(size: 13)).foregroundStyle(Color(hex: "#6b6b80"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickExisting(_ exercise: Exercise) {
        let we = WorkoutExercise(exercise: exercise)
        context.insert(we)
        if exercise.bodyPart == BodyPart.cardio.rawValue {
            we.distance = 0; we.cardioTimeSeconds = 0
        } else {
            let s = WorkoutSet(order: 1); context.insert(s); we.workoutSets.append(s)
        }
        onSelect(we); dismiss()
    }
}

// MARK: - New exercise sheet

struct NewExerciseSheet: View {
    let onAdd: (WorkoutExercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var selectedBodyPart: BodyPart = .legs
    @State private var exerciseName = ""
    @State private var cardioDistance = 0.0; @State private var cardioMinutes = 0
    @State private var timerMinutes = 0; @State private var timerSeconds = 0
    @State private var showImagePicker = false
    @State private var tempWorkoutExercise: WorkoutExercise?

    private var isCardio: Bool { selectedBodyPart == .cardio }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                Form {
                    Section("Группа мышц") {
                        Picker("", selection: $selectedBodyPart) {
                            ForEach(BodyPart.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        .pickerStyle(.wheel).frame(height: 120)
                    }
                    Section("Название") {
                        TextField("Название упражнения", text: $exerciseName)
                            .foregroundStyle(Color(hex: "#f0f0f5"))
                    }
                    if isCardio {
                        Section("Кардио") {
                            Stepper(value: $cardioDistance, in: 0...100, step: 0.5) {
                                Text("Дистанция: \(cardioDistance, specifier: "%.1f") км")
                            }
                            Stepper(value: $cardioMinutes, in: 0...600) {
                                Text("Время: \(cardioMinutes) мин")
                            }
                        }
                    } else {
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
                        footer: { Text("Запускается автоматически после каждого сета") }
                    }
                }
                .dismissKeyboardOnTap()
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Новое упражнение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        if let t = tempWorkoutExercise { context.delete(t) }
                        dismiss()
                    }.foregroundStyle(Color(hex: "#6b6b80"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") { addAndDismiss() }
                        .disabled(exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .foregroundStyle(Color(hex: "#ff5c3a")).fontWeight(.bold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func addAndDismiss() {
        let name = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let we: WorkoutExercise
        if let existing = tempWorkoutExercise {
            existing.exercise.name = name; existing.exercise.bodyPart = selectedBodyPart.rawValue; we = existing
        } else {
            let ex = Exercise.findOrCreate(name: name, bodyPart: selectedBodyPart.rawValue, in: context)
            we = WorkoutExercise(exercise: ex); context.insert(we)
        }
        if isCardio {
            we.distance = cardioDistance; we.cardioTimeSeconds = cardioMinutes * 60
        } else {
            let total = timerMinutes * 60 + timerSeconds
            we.timerSeconds = total > 0 ? total : nil
            let s = WorkoutSet(order: 1); context.insert(s); we.workoutSets.append(s)
        }
        onAdd(we); dismiss()
    }
}
