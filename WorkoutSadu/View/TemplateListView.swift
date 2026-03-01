import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TemplateListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.createdAt, order: .reverse) private var templates: [WorkoutTemplate]
    var onStartWorkout: ((Workout) -> Void)?

    @State private var showImporter = false
    @State private var importError: String?
    @State private var showImportError = false
    @State private var shareItems: [Any] = []
    @State private var isSharePresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                Group {
                    if templates.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.on.doc").font(.system(size: 48)).foregroundStyle(Color(hex: "#6b6b80"))
                            Text("Нет шаблонов").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color(hex: "#f0f0f5"))
                            Text("Открой тренировку → ••• → Сохранить шаблон").font(.system(size: 13)).foregroundStyle(Color(hex: "#6b6b80")).multilineTextAlignment(.center)
                        }
                        .padding(40)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(templates) { template in
                                    NavigationLink(destination: TemplateDetailView(template: template, onStart: {
                                        startWorkout(from: template)
                                    })) {
                                        templateCard(template)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(16)
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
            .navigationTitle("ШАБЛОНЫ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showImporter = true } label: {
                        Image(systemName: "square.and.arrow.down").foregroundStyle(Color(hex: "#6b6b80"))
                    }
                }
                if templates.count > 1 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { exportAll() } label: {
                            Image(systemName: "square.and.arrow.up").foregroundStyle(Color(hex: "#6b6b80"))
                        }
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType.json], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    for url in urls {
                        guard url.startAccessingSecurityScopedResource() else { continue }
                        defer { url.stopAccessingSecurityScopedResource() }
                        try? TemplateImporter.importJSON(from: url, into: context)
                    }
                }
            }
            .alert("Ошибка импорта", isPresented: $showImportError) {
                Button("OK", role: .cancel) {}
            } message: { Text(importError ?? "") }
            .sheet(isPresented: $isSharePresented) { ActivityViewController(activityItems: shareItems) }
        }
        .preferredColorScheme(.dark)
    }

    private func templateCard(_ template: WorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    let sorted = template.exercises.sorted { $0.order < $1.order }
                    Text(sorted.map(\.exerciseName).joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    startWorkout(from: template)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 12))
                        Text("Старт").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#ff5c3a"))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 14) {
                Label("\(template.exercises.count) упр.", systemImage: "figure.strengthtraining.traditional")
                let totalSets = template.exercises.reduce(0) { $0 + $1.defaultSets }
                Label("\(totalSets) сетов", systemImage: "repeat")
            }
            .font(.system(size: 11))
            .foregroundStyle(Color(hex: "#6b6b80"))
        }
        .padding(16)
        .darkCard()
        .contextMenu {
            Button { exportSingle(template) } label: { Label("Экспорт", systemImage: "square.and.arrow.up") }
            Button(role: .destructive) { context.delete(template) } label: { Label("Удалить", systemImage: "trash") }
        }
    }

    private func startWorkout(from template: WorkoutTemplate) {
        let workout = Workout(name: template.name, date: Date())
        context.insert(workout)
        for (i, te) in template.exercises.sorted(by: { $0.order < $1.order }).enumerated() {
            let ex = Exercise.findOrCreate(name: te.exerciseName, bodyPart: te.bodyPart, in: context)
            let we = WorkoutExercise(exercise: ex, timerSeconds: te.timerSeconds, order: i)
            we.targetWeight = te.defaultWeight
            we.targetReps = te.defaultReps
            we.targetSets = te.defaultSets
            context.insert(we)
            if te.bodyPart != BodyPart.cardio.rawValue {
                for j in 1...max(te.defaultSets, 1) {
                    let s = WorkoutSet(order: j, reps: te.defaultReps, weight: te.defaultWeight)
                    context.insert(s); we.workoutSets.append(s)
                }
            }
            workout.workoutExercises.append(we)
        }
        onStartWorkout?(workout)
    }

    private func bodyPartIcon(_ part: String) -> String {
        switch part {
        case BodyPart.chest.rawValue: return "figure.strengthtraining.traditional"
        case BodyPart.back.rawValue: return "figure.rowing"
        case BodyPart.legs.rawValue: return "figure.run"
        case BodyPart.shoulders.rawValue: return "figure.boxing"
        case BodyPart.arms.rawValue: return "figure.mixed.cardio"
        case BodyPart.abs.rawValue: return "figure.core.training"
        case BodyPart.cardio.rawValue: return "heart.fill"
        default: return "dumbbell.fill"
        }
    }

    private func exportSingle(_ template: WorkoutTemplate) {
        guard let data = try? JSONEncoder().encode(TemplateExport(from: template)) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(template.name).json")
        try? data.write(to: url)
        shareItems = [url as NSURL]; isSharePresented = true
    }
    private func exportAll() {
        guard let data = try? TemplateImporter.exportJSON(templates: Array(templates)) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("templates.json")
        try? data.write(to: url)
        shareItems = [url as NSURL]; isSharePresented = true
    }
}

// MARK: - Template Detail

struct TemplateDetailView: View {
    @Bindable var template: WorkoutTemplate
    var onStart: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var isEditing = false
    @State private var editName: String = ""

    private var sorted: [TemplateExercise] {
        template.exercises.sorted { $0.order < $1.order }
    }

    private var totalSets: Int { template.exercises.reduce(0) { $0 + $1.defaultSets } }
    private var totalVolume: Double {
        template.exercises.reduce(0.0) { $0 + Double($1.defaultSets) * Double($1.defaultReps) * $1.defaultWeight }
    }

    var body: some View {
        ZStack {
            Color(hex: "#0e0e12").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    if isEditing { nameField }
                    statsHeader
                    exercisesList
                }
                .padding(16)
                .padding(.bottom, 90)
            }

            VStack {
                Spacer()
                Button {
                    onStart()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill").font(.system(size: 14))
                        Text("Начать тренировку").font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "#ff5c3a"))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#0e0e12").opacity(0), Color(hex: "#0e0e12")],
                        startPoint: .top, endPoint: .center
                    )
                    .frame(height: 60)
                    .allowsHitTesting(false),
                    alignment: .top
                )
            }
        }
        .navigationTitle(isEditing ? "Редактирование" : template.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if isEditing {
                        let trimmed = editName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { template.name = trimmed }
                        reindexOrders()
                    } else {
                        editName = template.name
                    }
                    withAnimation(.easeInOut(duration: 0.2)) { isEditing.toggle() }
                } label: {
                    Text(isEditing ? "Готово" : "Изменить")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Name field

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("НАЗВАНИЕ")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)
            TextField("Название шаблона", text: $editName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: "#f0f0f5"))
        }
        .padding(16)
        .darkCard()
    }

    // MARK: - Stats header

    private var statsHeader: some View {
        HStack(spacing: 0) {
            statCell(value: "\(sorted.count)", label: "Упражнений")
            vDivider
            statCell(value: "\(totalSets)", label: "Сетов")
            vDivider
            statCell(value: formatVolume(totalVolume), label: "Объём")
        }
        .padding(.vertical, 16)
        .darkCard()
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: "#ff5c3a"))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    private var vDivider: some View {
        Rectangle()
            .fill(Color(hex: "#6b6b80").opacity(0.2))
            .frame(width: 1, height: 32)
    }

    // MARK: - Exercise list

    private var exercisesList: some View {
        VStack(spacing: 0) {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, ex in
                if isEditing {
                    editableRow(ex, number: idx + 1, isFirst: idx == 0, isLast: idx == sorted.count - 1)
                } else {
                    exerciseRow(ex, number: idx + 1)
                }
                if idx < sorted.count - 1 {
                    Divider().padding(.leading, isEditing ? 16 : 56)
                }
            }
        }
        .darkCard()
    }

    // MARK: - View-only row

    private func exerciseRow(_ ex: TemplateExercise, number: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "#ff5c3a"))
                .frame(width: 26, height: 26)
                .background(Color(hex: "#ff5c3a").opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(ex.exerciseName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
                Text(ex.bodyPart)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#6b6b80"))
            }

            Spacer()

            if ex.bodyPart == BodyPart.cardio.rawValue {
                Text("Кардио")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#6b6b80"))
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(ex.defaultSets) × \(ex.defaultReps)")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    if ex.defaultWeight > 0 {
                        Text("\(ex.defaultWeight, specifier: "%.1f") кг")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                    }
                }
            }

            if let timer = ex.timerSeconds, timer > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "timer").font(.system(size: 9))
                    Text(formatTimer(timer)).font(.system(size: 10))
                }
                .foregroundStyle(Color(hex: "#6b6b80"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Editable row

    private func editableRow(_ ex: TemplateExercise, number: Int, isFirst: Bool, isLast: Bool) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(spacing: 4) {
                    Button { moveUp(ex) } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isFirst ? Color(hex: "#6b6b80").opacity(0.3) : Color(hex: "#6b6b80"))
                    }
                    .disabled(isFirst)
                    Button { moveDown(ex) } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isLast ? Color(hex: "#6b6b80").opacity(0.3) : Color(hex: "#6b6b80"))
                    }
                    .disabled(isLast)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text(ex.exerciseName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    Text(ex.bodyPart)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }

                Spacer()

                Button { deleteExercise(ex) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                }
                .buttonStyle(.plain)
            }

            if ex.bodyPart != BodyPart.cardio.rawValue {
                HStack(spacing: 8) {
                    editField("Сеты", value: Binding(
                        get: { Double(ex.defaultSets) },
                        set: { ex.defaultSets = max(1, Int($0)) }
                    ), step: 1)

                    editField("Повт", value: Binding(
                        get: { Double(ex.defaultReps) },
                        set: { ex.defaultReps = max(1, Int($0)) }
                    ), step: 1)

                    editField("Вес", value: Binding(
                        get: { ex.defaultWeight },
                        set: { ex.defaultWeight = max(0, $0) }
                    ), step: 2.5, suffix: "кг")

                    editField("Отдых", value: Binding(
                        get: { Double(ex.timerSeconds ?? 0) },
                        set: { ex.timerSeconds = Int($0) > 0 ? Int($0) : nil }
                    ), step: 15, suffix: "с")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func editField(_ label: String, value: Binding<Double>, step: Double, suffix: String = "") -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(0.5)
            HStack(spacing: 4) {
                Button { value.wrappedValue = max(0, value.wrappedValue - step) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                let display = step >= 1
                    ? "\(Int(value.wrappedValue))\(suffix)"
                    : String(format: "%.1f%@", value.wrappedValue, suffix)
                Text(display)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
                    .frame(minWidth: 36)

                Button { value.wrappedValue += step } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Actions

    private func moveUp(_ ex: TemplateExercise) {
        let s = sorted
        guard let idx = s.firstIndex(where: { $0.id == ex.id }), idx > 0 else { return }
        let prev = s[idx - 1]
        let tmp = ex.order; ex.order = prev.order; prev.order = tmp
    }

    private func moveDown(_ ex: TemplateExercise) {
        let s = sorted
        guard let idx = s.firstIndex(where: { $0.id == ex.id }), idx < s.count - 1 else { return }
        let next = s[idx + 1]
        let tmp = ex.order; ex.order = next.order; next.order = tmp
    }

    private func deleteExercise(_ ex: TemplateExercise) {
        context.delete(ex)
    }

    private func reindexOrders() {
        for (i, ex) in sorted.enumerated() { ex.order = i }
    }

    // MARK: - Helpers

    private func formatVolume(_ v: Double) -> String {
        if v <= 0 { return "—" }
        return v >= 1000 ? String(format: "%.1fт", v / 1000) : String(format: "%.0fкг", v)
    }

    private func formatTimer(_ s: Int) -> String {
        s >= 60 ? "\(s / 60)м\(s % 60 > 0 ? "\(s % 60)с" : "")" : "\(s)с"
    }
}
