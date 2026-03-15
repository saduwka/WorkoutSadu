import SwiftUI
import SwiftData
import Charts

struct ExerciseView: View {
    @Bindable var workoutExercise: WorkoutExercise
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(GymBroManager.self) private var gymBro
    @ObservedObject private var timerManager = TimerManager.shared
    @State private var showImagePicker = false
    @State private var showEditSheet = false
    @State private var prResult: PRResult?
    @State private var showPRCelebration = false
    @State private var showHistory = false
    @State private var gifData: Data?
    @State private var gifExpanded = true

    private var isCardio: Bool { workoutExercise.exercise.bodyPart == BodyPart.cardio.rawValue }
    private var sortedSets: [WorkoutSet] { workoutExercise.workoutSets.sorted { $0.order < $1.order } }

    private var historyPoints: [(date: Date, weight: Double)] {
        let exerciseName = workoutExercise.exercise.name
        let bodyPart = workoutExercise.exercise.bodyPart
        let descriptor = FetchDescriptor<WorkoutExercise>()
        guard let all = try? context.fetch(descriptor) else { return [] }
        var points: [(Date, Double)] = []
        for we in all {
            guard we.exercise.name == exerciseName,
                  we.exercise.bodyPart == bodyPart,
                  let workout = we.workout else { continue }
            let maxW = we.workoutSets.filter { $0.isCompleted }.map(\.weight).max() ?? 0
            guard maxW > 0 else { continue }
            points.append((workout.date, maxW))
        }
        return points.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        ZStack {
            Color(hex: "#0e0e12").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    // GIF demonstration
                    if let data = gifData {
                        VStack(spacing: 0) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { gifExpanded.toggle() }
                            } label: {
                                HStack {
                                    Text("ДЕМОНСТРАЦИЯ")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color(hex: "#6b6b80"))
                                        .tracking(1)
                                    Spacer()
                                    Image(systemName: gifExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color(hex: "#6b6b80"))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if gifExpanded {
                                AnimatedGifView(data: data)
                                    .frame(height: 220)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 14)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .darkCard()
                    }

                    // Rest timer
                    if timerManager.isRunning, timerManager.exerciseID == workoutExercise.id.uuidString {
                        VStack(spacing: 8) {
                            Text("ОТДЫХ")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .tracking(1)
                            Text(timerManager.timeString())
                                .font(.system(size: 56, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(hex: "#ff5c3a"))
                            Button("Пропустить") { timerManager.stop() }
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .darkCard(accentBorder: Color(hex: "#ff5c3a").opacity(0.3))
                    }

                    // PR banner
                    if !isCardio, let best = PRManager.bestWeight(for: workoutExercise.exercise, in: context), best > 0 {
                        HStack {
                            Image(systemName: "trophy.fill").foregroundStyle(Color(hex: "#ffb830"))
                            Text("Личный рекорд")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: "#f0f0f5"))
                            Spacer()
                            Text(String(format: "%.1f кг", best))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color(hex: "#ffb830"))
                        }
                        .padding(14)
                        .darkCard(accentBorder: Color(hex: "#ffb830").opacity(0.3))
                    }

                    // History chart
                    if !isCardio && historyPoints.count >= 2 {
                        VStack(spacing: 0) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { showHistory.toggle() }
                            } label: {
                                HStack {
                                    label("ПРОГРЕСС ВЕСА")
                                    Spacer()
                                    Image(systemName: showHistory ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color(hex: "#6b6b80"))
                                        .padding(.trailing, 16)
                                        .padding(.top, 14)
                                }
                            }
                            .buttonStyle(.plain)

                            if showHistory {
                                Chart(historyPoints.indices, id: \.self) { i in
                                    let p = historyPoints[i]
                                    LineMark(
                                        x: .value("Дата", p.date),
                                        y: .value("Вес", p.weight)
                                    )
                                    .foregroundStyle(Color(hex: "#ff5c3a"))
                                    .interpolationMethod(.catmullRom)
                                    AreaMark(
                                        x: .value("Дата", p.date),
                                        y: .value("Вес", p.weight)
                                    )
                                    .foregroundStyle(Color(hex: "#ff5c3a").opacity(0.12))
                                    .interpolationMethod(.catmullRom)
                                    PointMark(
                                        x: .value("Дата", p.date),
                                        y: .value("Вес", p.weight)
                                    )
                                    .foregroundStyle(Color(hex: "#ff5c3a"))
                                    .symbolSize(20)
                                }
                                .chartYAxisLabel("кг")
                                .chartXAxis {
                                    AxisMarks(values: .automatic(desiredCount: 4)) {
                                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                            .foregroundStyle(Color(hex: "#6b6b80"))
                                    }
                                }
                                .chartYAxis {
                                    AxisMarks {
                                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                                        AxisValueLabel().foregroundStyle(Color(hex: "#6b6b80"))
                                    }
                                }
                                .frame(height: 160)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 14)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .darkCard()
                    }

                    // Cardio — метрики из JSON-конфига (CardioPresets по имени упражнения)
                    if isCardio {
                        cardioCard
                    } else {
                        // Sets
                        VStack(spacing: 0) {
                            HStack {
                                label("СЕТЫ")
                                Spacer()
                                let done = workoutExercise.completedSetsCount
                                Text("\(done) из \(sortedSets.count)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(hex: "#6b6b80"))
                                    .padding(.trailing, 16)
                            }

                            ForEach(sortedSets) { set in
                                SetRow(set: set,
                                       setNumber: (sortedSets.firstIndex { $0.id == set.id } ?? 0) + 1,
                                       onComplete: { completeSet(set) })
                                .padding(.horizontal, 16)
                                .overlay(Divider().padding(.leading, 16), alignment: .bottom)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { context.delete(set) } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                            }

                            Button {
                                addSet()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill").foregroundStyle(Color(hex: "#ff5c3a"))
                                    Text("Добавить сет").font(.system(size: 15, weight: .medium)).foregroundStyle(Color(hex: "#ff5c3a"))
                                    Spacer()
                                }
                                .padding(16)
                            }
                        }
                        .darkCard()
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        label("ЗАМЕТКИ")
                        TextField("Добавить заметку...", text: Binding(
                            get: { workoutExercise.note ?? "" },
                            set: { workoutExercise.note = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                        .lineLimit(1...5)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                    }
                    .darkCard()

                    // Photo
                    VStack(alignment: .leading, spacing: 8) {
                        label("ФОТО")
                        if let data = workoutExercise.photo, let img = UIImage(data: data) {
                            Image(uiImage: img)
                                .resizable().scaledToFit()
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal, 16)
                            Button("Удалить фото", role: .destructive) { workoutExercise.photo = nil }
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "#ff5c3a"))
                                .padding(.horizontal, 16).padding(.bottom, 14)
                        } else {
                            Button("Добавить фото") { showImagePicker = true }
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color(hex: "#ff5c3a"))
                                .padding(.horizontal, 16).padding(.bottom, 14)
                        }
                    }
                    .darkCard()
                }
                .dismissKeyboardOnTap()
                .padding(16)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)

            if showPRCelebration, let pr = prResult {
                PRCelebrationView(result: pr) {
                    withAnimation { showPRCelebration = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .navigationTitle(workoutExercise.exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showEditSheet = true } label: {
                    Image(systemName: "gearshape").foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        NotificationCenter.default.post(name: .openGymBroChat, object: nil)
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: "#4a8cff"))
                    }
                    Button("Готово") { removeIncompleteSets(); dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                }
            }
        }
        .fullScreenCover(isPresented: $showImagePicker) { ImagePicker(workoutExercise: workoutExercise) }
        .sheet(isPresented: $showEditSheet) { ExerciseEditView(workoutExercise: workoutExercise) }
        .onChange(of: showEditSheet) { _, showing in
            if !showing {
                Task {
                    if let url = workoutExercise.exercise.gifURL, !url.isEmpty {
                        gifData = await ExerciseGifManager.shared.loadGif(from: url)
                    } else {
                        gifData = nil
                    }
                }
            }
        }
        .task {
            if let url = workoutExercise.exercise.gifURL, !url.isEmpty {
                gifData = await ExerciseGifManager.shared.loadGif(from: url)
            }
        }
        .onAppear {
            gymBro.screenContext = "Упражнение: \(workoutExercise.exercise.name)"
            gymBro.screenContextImage = workoutExercise.photo
        }
        .onDisappear {
            gymBro.screenContext = nil
            gymBro.screenContextImage = nil
        }
        .preferredColorScheme(.dark)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(hex: "#6b6b80"))
            .tracking(1)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private var cardioCard: some View {
        let config = CardioPresetsLoader.config(forExerciseName: workoutExercise.exercise.name)
        return VStack(spacing: 0) {
            label("КАРДИО")
            ForEach(Array(config.metrics.enumerated()), id: \.element.id) { index, metric in
                if index > 0 { Divider().padding(.leading, 16) }
                cardioRow(
                    title: metric.label,
                    value: cardioBinding(for: metric),
                    step: metric.step,
                    unit: metric.unit,
                    range: (metric.min ?? 0)...metric.max
                )
            }
        }
        .darkCard()
    }

    private func cardioBinding(for metric: CardioMetricConfig) -> Binding<Double> {
        let isTimeSeconds = metric.valueType == "timeSeconds"
        return Binding(
            get: {
                let raw = workoutExercise.getCardioValue(for: metric.id) ?? 0
                return isTimeSeconds ? raw / 60 : raw
            },
            set: { newValue in
                let value = isTimeSeconds ? newValue * 60 : newValue
                workoutExercise.setCardioValue(for: metric.id, value)
            }
        )
    }

    private func cardioRow(title: String, value: Binding<Double>, step: Double, unit: String, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundStyle(Color(hex: "#f0f0f5"))
            Spacer()
            Stepper(value: value, in: range, step: step) {
                Text(unit.isEmpty ? "\(value.wrappedValue, specifier: step < 1 ? "%.1f" : "%.0f")" : "\(value.wrappedValue, specifier: step < 1 ? "%.1f" : "%.0f") \(unit)")
                    .font(.system(size: 14)).foregroundStyle(Color(hex: "#6b6b80"))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func removeIncompleteSets() {
        workoutExercise.workoutSets.filter { !$0.isCompleted }.forEach { context.delete($0) }
    }
    private func addSet() {
        let last = sortedSets.last
        let s = WorkoutSet(order: (last?.order ?? 0) + 1, reps: last?.reps ?? 10, weight: last?.weight ?? 0)
        context.insert(s); workoutExercise.workoutSets.append(s)
    }
    private func completeSet(_ set: WorkoutSet) {
        set.isCompleted = true; set.completedAt = Date()
        // Если пользователь не нажал «Начать» — запускаем время тренировки при первом отмеченном подходе
        if let w = workoutExercise.workout, w.startedAt == nil {
            w.startedAt = set.completedAt
            try? context.save()
        }
        if let pr = PRManager.check(set: set, exercise: workoutExercise.exercise, in: context) {
            prResult = pr
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { showPRCelebration = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { showPRCelebration = false } }
        }

        if let s = workoutExercise.timerSeconds, s > 0 { timerManager.start(seconds: s, exerciseID: workoutExercise.id.uuidString) }
        if sortedSets.last?.id == set.id {
            let s = WorkoutSet(order: set.order + 1, reps: set.reps, weight: set.weight)
            context.insert(s); workoutExercise.workoutSets.append(s)
        }
    }
}

// MARK: - PR Celebration

struct PRCelebrationView: View {
    let result: PRResult
    let onDismiss: () -> Void
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { onDismiss() }
            VStack(spacing: 16) {
                Text("🏆").font(.system(size: 64))
                Text("НОВЫЙ РЕКОРД!")
                    .font(.custom("BebasNeue-Regular", size: 36))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
                ForEach(result.types, id: \.rawValue) { type in
                    HStack(spacing: 8) {
                        Image(systemName: type == .weight ? "scalemass.fill" : "flame.fill")
                            .foregroundStyle(type == .weight ? Color(hex: "#5b8cff") : Color(hex: "#ff5c3a"))
                        if type == .weight, let w = result.newMaxWeight {
                            Text(String(format: "%.1f кг", w)).font(.title2.bold()).foregroundStyle(.white)
                        } else if let v = result.newMaxVolume {
                            Text(String(format: "%.0f кг объём", v)).font(.title2.bold()).foregroundStyle(.white)
                        }
                    }
                }
                Text("Нажми чтобы закрыть").font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            .padding(32)
            .background(Color(hex: "#16161d").opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(hex: "#ffb830").opacity(0.4), lineWidth: 1))
            .scaleEffect(scale).opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { scale = 1; opacity = 1 }
            }
        }
    }
}

// MARK: - Set Row

struct SetRow: View {
    @Bindable var set: WorkoutSet
    let setNumber: Int
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(setNumber)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .frame(width: 24)

            // Weight
            VStack(spacing: 2) {
                Text("кг").font(.caption2).foregroundStyle(Color(hex: "#6b6b80"))
                HStack(spacing: 6) {
                    Button { set.weight = max(0, set.weight - 2.5) } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Color(hex: "#6b6b80"))
                    }.buttonStyle(.borderless)
                    Text("\(set.weight, specifier: "%.1f")")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                        .frame(minWidth: 50)
                    Button { set.weight += 2.5 } label: {
                        Image(systemName: "plus.circle").foregroundStyle(Color(hex: "#6b6b80"))
                    }.buttonStyle(.borderless)
                }
            }

            Rectangle().frame(width: 1).foregroundStyle(Color(hex: "#6b6b80").opacity(0.2)).frame(height: 30)

            // Reps
            VStack(spacing: 2) {
                Text("повт").font(.caption2).foregroundStyle(Color(hex: "#6b6b80"))
                HStack(spacing: 6) {
                    Button { set.reps = max(1, set.reps - 1) } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Color(hex: "#6b6b80"))
                    }.buttonStyle(.borderless)
                    Text("\(set.reps)")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                        .frame(minWidth: 28)
                    Button { set.reps += 1 } label: {
                        Image(systemName: "plus.circle").foregroundStyle(Color(hex: "#6b6b80"))
                    }.buttonStyle(.borderless)
                }
            }

            Spacer()

            Button {
                guard !set.isCompleted else { return }
                onComplete()
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.isCompleted ? Color(hex: "#3aff9e") : Color(hex: "#6b6b80"))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 12)
        .opacity(set.isCompleted ? 0.45 : 1)
    }
}
