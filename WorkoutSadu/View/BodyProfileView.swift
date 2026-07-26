import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

struct BodyProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [BodyProfile]
    @Query private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @Query private var workoutExercises: [WorkoutExercise]
    @Query private var workoutSets: [WorkoutSet]
    @Query private var templates: [WorkoutTemplate]
    @Query(sort: \WeightEntry.date) private var weightEntries: [WeightEntry]

    @State private var isEditing = false
    @State private var confirmAction: DataCleanAction?
    @State private var newWeightText = ""
    @State private var showAddWeight = false
    @State private var isRestoring = false
    @State private var restoreError: String?
    @State private var restoreSuccessMessage: String?
    @State private var showBackupImporter = false
    @State private var pendingBackupURL: URL?

    enum DataCleanAction: Identifiable {
        case workouts, exercises, templates, everything, restore, exportCloud, importFile, exportHome
        var id: Int { hashValue }
    }

    @State private var homeBackupEnabled = HomeBackupService.shared.isEnabled
    @State private var homeLanURL = HomeBackupService.shared.lanBaseURL
    @State private var homeTailscaleURL = HomeBackupService.shared.tailscaleBaseURL
    @State private var homeToken = HomeBackupService.shared.token
    @State private var homeLastSuccessTick = 0
    @AppStorage("userDisplayName") private var userDisplayName = ""

    private var profile: BodyProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        displayNameCard
                        // Profile card
                        if let p = profile {
                            profileCard(p)
                            calculatedMetrics(p)
                        }
                        // Weight history
                        weightHistoryCard
                        // HealthKit sync
                        healthKitSyncCard
                        // Data management
                        dataManagementCard
                        homeBackupCard
                    }
                    .dismissKeyboardOnTap()
                    .padding(16)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("ПРОФИЛЬ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Изменить") { isEditing = true }
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $isEditing) {
                if let p = profile { BodyProfileEditView(profile: p) }
            }
            .task { if profiles.isEmpty { context.insert(BodyProfile()) } }
            .alert("Записать вес", isPresented: $showAddWeight) {
                TextField("кг", text: $newWeightText).keyboardType(.decimalPad)
                Button("Сохранить") {
                    if let w = Double(newWeightText.replacingOccurrences(of: ",", with: ".")), w > 0 {
                        context.insert(WeightEntry(weight: w))
                        if let p = profile {
                            p.weight = w
                            p.updatedAt = Date()
                            if p.healthKitEnabled {
                                Task { await HealthKitManager.shared.saveWeight(w, date: Date()) }
                            }
                        }
                    }
                    newWeightText = ""
                }
                Button("Отмена", role: .cancel) { newWeightText = "" }
            } message: { Text("Введите текущий вес в кг") }
            .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirmAction != nil }, set: { if !$0 { confirmAction = nil } }), titleVisibility: .visible) {
                Button(confirmActionButtonTitle, role: confirmActionIsDestructive ? .destructive : nil) {
                    if let a = confirmAction { performClean(a); confirmAction = nil }
                }
                Button("Отмена", role: .cancel) { confirmAction = nil }
            } message: { Text(confirmMessage) }
            .fileImporter(
                isPresented: $showBackupImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    pendingBackupURL = url
                    confirmAction = .importFile
                case .failure(let error):
                    restoreError = error.localizedDescription
                }
            }
            .alert("Готово", isPresented: Binding(get: { restoreSuccessMessage != nil }, set: { if !$0 { restoreSuccessMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                if let msg = restoreSuccessMessage { Text(msg) }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Display name

    private var displayNameCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ИМЯ")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)
            TextField("Как к тебе обращаться", text: $userDisplayName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: "#f0f0f5"))
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .darkCard()
    }

    private func profileCard(_ p: BodyProfile) -> some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("МОИ ДАННЫЕ")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "#6b6b80")).tracking(1)
                    if let bmi = p.bmi {
                        Text(p.bmiCategory).font(.custom("BebasNeue-Regular", size: 22))
                            .foregroundStyle(bmiColor(bmi))
                    }
                }
                Spacer()
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(hex: "#ff5c3a").opacity(0.6))
            }
            Divider().background(Color(hex: "#6b6b80").opacity(0.3))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                infoCell("Вес", p.weight > 0 ? String(format: "%.1f кг", p.weight) : "—")
                infoCell("Рост", p.height > 0 ? String(format: "%.0f см", p.height) : "—")
                infoCell("Возраст", p.effectiveAge > 0 ? "\(p.effectiveAge) лет" : "—")
                infoCell("Пол", p.gender.title)
                infoCell("ЧСС покоя", p.restingHeartRate > 0 ? "\(p.restingHeartRate) уд/мин" : "—")
            }
            if let goal = p.goal {
                HStack {
                    Text("Цель").font(.system(size: 11)).foregroundStyle(Color(hex: "#6b6b80"))
                    Spacer()
                    Text(goal.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: "#f0f0f5"))
                }
                .padding(.top, 4)
            }
        }
        .padding(18).darkCard()
    }

    private func infoCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Color(hex: "#6b6b80"))
            Text(value).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(hex: "#f0f0f5"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(Color(hex: "#1e1e28"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func calculatedMetrics(_ p: BodyProfile) -> some View {
        VStack(spacing: 0) {
            metricRow("BMI", p.bmi.map { String(format: "%.1f · \(p.bmiCategory)", $0) } ?? "—",
                      color: p.bmi.map { bmiColor($0) })
            Divider().padding(.leading, 16)
            metricRow("Норма по росту", p.idealWeightRange.map { String(format: "%.0f–%.0f кг", $0.lowerBound, $0.upperBound) } ?? "—", color: nil)
            if let target = p.displayTargetWeight {
                Divider().padding(.leading, 16)
                metricRow("Цель по весу", String(format: "%.1f кг", target), color: Color(hex: "#5b8cff"))
                if let delta = p.weightDeltaFromTarget, abs(delta) >= 0.5 {
                    Divider().padding(.leading, 16)
                    metricRow("До цели", delta > 0 ? String(format: "−%.1f кг", delta) : String(format: "+%.1f кг", -delta),
                              color: delta > 0 ? Color(hex: "#3aff9e") : Color(hex: "#ffb830"))
                }
            }
            Divider().padding(.leading, 16)
            metricRow("Макс. ЧСС", p.maxHeartRate.map { "\($0) уд/мин" } ?? "—", color: nil)
        }
        .darkCard()
    }

    private func metricRow(_ label: String, _ value: String, color: Color?) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(Color(hex: "#6b6b80"))
            Spacer()
            Text(value).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color ?? Color(hex: "#f0f0f5"))
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private var weightHistoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("ИСТОРИЯ ВЕСА")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "#6b6b80")).tracking(1)
                Spacer()
                Text("\(weightEntries.count) записей")
                    .font(.system(size: 11)).foregroundStyle(Color(hex: "#6b6b80"))
            }

            if weightEntries.count >= 2 {
                Chart(weightEntries) { e in
                    LineMark(x: .value("Дата", e.date), y: .value("Вес", e.weight))
                        .foregroundStyle(Color(hex: "#5b8cff")).interpolationMethod(.catmullRom)
                    PointMark(x: .value("Дата", e.date), y: .value("Вес", e.weight))
                        .foregroundStyle(Color(hex: "#5b8cff")).symbolSize(20)
                    AreaMark(x: .value("Дата", e.date), y: .value("Вес", e.weight))
                        .foregroundStyle(Color(hex: "#5b8cff").opacity(0.1)).interpolationMethod(.catmullRom)
                }
                .chartYAxisLabel("кг")
                .frame(height: 140)
            }

            ForEach(weightEntries.suffix(5).reversed()) { e in
                HStack {
                    Text(e.date, format: .dateTime.day().month(.abbreviated))
                        .font(.system(size: 13)).foregroundStyle(Color(hex: "#6b6b80"))
                    Spacer()
                    Text(String(format: "%.1f кг", e.weight))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: "#f0f0f5"))
                }
                .padding(.vertical, 4)
            }

            Button {
                showAddWeight = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Color(hex: "#ff5c3a"))
                    Text("Записать вес").font(.system(size: 15, weight: .medium)).foregroundStyle(Color(hex: "#ff5c3a"))
                }
            }
        }
        .padding(18).darkCard()
    }

    private var healthKitSyncCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "heart.fill").foregroundStyle(Color.red)
                Text("APPLE HEALTH")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "#6b6b80")).tracking(1)
            }

            Toggle("Синхронизация", isOn: Binding(
                get: { profile?.healthKitEnabled ?? false },
                set: { newValue in
                    if let p = profile {
                        p.healthKitEnabled = newValue
                        if newValue {
                            Task {
                                try? await HealthKitManager.shared.requestAuthorization()
                            }
                        }
                    }
                }
            ))
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color(hex: "#f0f0f5"))
            .tint(Color(hex: "#ff5c3a"))

            Text("Синхронизация тренировок, веса, воды и калорий с приложением Здоровье.")
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
        .padding(18).darkCard()
    }

    private var dataManagementCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ДАННЫЕ")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "#6b6b80")).tracking(1)
                Spacer()
                if isRestoring {
                    ProgressView().tint(Color(hex: "#ff5c3a")).scaleEffect(0.7)
                } else {
                    Text("тр: \(workouts.count) · упр: \(exercises.count) · сетов: \(workoutSets.count)")
                        .font(.system(size: 10)).foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

            Button {
                confirmAction = .restore
            } label: {
                HStack {
                    Image(systemName: "cloud.arrow.down").foregroundStyle(Color(hex: "#5b8cff"))
                    Text("Восстановить из облака").font(.system(size: 14, weight: .medium)).foregroundStyle(Color(hex: "#5b8cff"))
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            Divider().padding(.leading, 16)

            Button {
                confirmAction = .exportCloud
            } label: {
                HStack {
                    Image(systemName: "icloud.and.arrow.up").foregroundStyle(Color(hex: "#ffb830"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Сохранить в облако").font(.system(size: 14, weight: .medium)).foregroundStyle(Color(hex: "#ffb830"))
                        if let date = FirebaseBackupService.shared.lastExportDate {
                            Text("Последний бэкап: \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            Divider().padding(.leading, 16)

            Button {
                showBackupImporter = true
            } label: {
                HStack {
                    Image(systemName: "doc.badge.arrow.up").foregroundStyle(Color(hex: "#3aff9e"))
                    Text("Импорт из файла").font(.system(size: 14, weight: .medium)).foregroundStyle(Color(hex: "#3aff9e"))
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            Divider().padding(.leading, 16)

            deleteRow("Удалить все тренировки", count: workouts.count) { confirmAction = .workouts }
            Divider().padding(.leading, 16)
            deleteRow("Удалить все упражнения", count: exercises.count) { confirmAction = .exercises }
            Divider().padding(.leading, 16)
            deleteRow("Удалить все шаблоны", count: templates.count) { confirmAction = .templates }
            Divider().padding(.leading, 16)
            Button(role: .destructive) { confirmAction = .everything } label: {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Color(hex: "#ff5c3a"))
                    Text("Сбросить всё").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: "#ff5c3a"))
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
        }
        .darkCard()
        .alert("Ошибка восстановления", isPresented: Binding(get: { restoreError != nil }, set: { if !$0 { restoreError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let err = restoreError { Text(err) }
        }
    }

    private var homeBackupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RASPBERRY PI")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)

            Toggle("Бэкап на Raspberry Pi", isOn: $homeBackupEnabled)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: "#f0f0f5"))
                .tint(Color(hex: "#ff5c3a"))
                .onChange(of: homeBackupEnabled) { _, v in
                    HomeBackupService.shared.isEnabled = v
                    if v { HomeBackupService.scheduleNextBGTask() }
                }

            Text("Автоночью (~03:00) только по домашней Wi‑Fi. Если не достучались — уведомление включить Tailscale и сохранить вручную.")
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "#6b6b80"))

            labeledField("LAN URL", text: $homeLanURL, placeholder: "http://192.168.10.30:8787")
                .onChange(of: homeLanURL) { _, v in HomeBackupService.shared.lanBaseURL = v }

            labeledField("Tailscale URL", text: $homeTailscaleURL, placeholder: "http://100.99.85.87:8787")
                .onChange(of: homeTailscaleURL) { _, v in HomeBackupService.shared.tailscaleBaseURL = v }

            VStack(alignment: .leading, spacing: 6) {
                Text("ТОКЕН")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .tracking(1)
                SecureField("BACKUP_TOKEN", text: $homeToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
                    .padding(12)
                    .background(Color(hex: "#1a1a22"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onChange(of: homeToken) { _, v in HomeBackupService.shared.token = v }
            }

            Button {
                confirmAction = .exportHome
            } label: {
                HStack {
                    Image(systemName: "externaldrive.badge.plus").foregroundStyle(Color(hex: "#5b8cff"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Сохранить на Raspberry Pi")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: "#5b8cff"))
                        if let date = HomeBackupService.shared.lastSuccessDate {
                            Text("Последний: \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .id(homeLastSuccessTick)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(isRestoring)
        }
        .padding(18)
        .darkCard()
    }

    private func labeledField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#f0f0f5"))
                .padding(12)
                .background(Color(hex: "#1a1a22"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func deleteRow(_ label: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            HStack {
                Text(label).font(.system(size: 14)).foregroundStyle(Color(hex: "#ff5c3a").opacity(0.8))
                Spacer()
                Text("\(count)").font(.system(size: 13)).foregroundStyle(Color(hex: "#6b6b80"))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private var confirmActionIsDestructive: Bool {
        switch confirmAction {
        case .workouts, .exercises, .templates, .everything, .restore, .importFile: return true
        default: return false
        }
    }

    private var confirmActionButtonTitle: String {
        switch confirmAction {
        case .restore: return "Восстановить"
        case .exportCloud, .exportHome: return "Сохранить"
        case .importFile: return "Импортировать"
        case .workouts, .exercises, .templates, .everything: return "Удалить"
        case nil: return "OK"
        }
    }

    private var confirmTitle: String {
        switch confirmAction {
        case .workouts: return "Удалить все тренировки?"
        case .exercises: return "Удалить все упражнения?"
        case .templates: return "Удалить все шаблоны?"
        case .everything: return "Сбросить всё?"
        case .restore: return "Восстановить из облака?"
        case .exportCloud: return "Сохранить в облако?"
        case .importFile: return "Импортировать бэкап?"
        case .exportHome: return "Сохранить на Raspberry Pi?"
        case nil: return ""
        }
    }
    private var confirmMessage: String {
        switch confirmAction {
        case .workouts: return "Будет удалено \(workouts.count) тренировок. Это необратимо."
        case .exercises: return "Будет удалено \(exercises.count) упражнений."
        case .templates: return "Будет удалено \(templates.count) шаблонов."
        case .everything: return "Все тренировки, упражнения и шаблоны будут удалены. Профиль сохранится."
        case .restore: return "Текущие данные будут полностью заменены данными из Firebase. Это нельзя отменить."
        case .exportCloud: return "Текущие тренировки, упражнения и остальные данные будут загружены в Firebase Storage (latest.json)."
        case .importFile: return "Текущие данные будут полностью заменены данными из выбранного latest.json. Это нельзя отменить."
        case .exportHome: return "Сначала попытка по домашней Wi‑Fi, если не получится — через Tailscale URL."
        case nil: return ""
        }
    }
    private func performClean(_ action: DataCleanAction) {
        switch action {
        case .workouts: workouts.forEach { context.delete($0) }; workoutExercises.filter { $0.workout == nil }.forEach { context.delete($0) }
        case .exercises: exercises.forEach { context.delete($0) }
        case .templates: templates.forEach { context.delete($0) }
        case .everything: workouts.forEach { context.delete($0) }; workoutExercises.forEach { context.delete($0) }; workoutSets.forEach { context.delete($0) }; exercises.forEach { context.delete($0) }; templates.forEach { context.delete($0) }
        case .restore:
            Task {
                isRestoring = true
                do {
                    try await FirebaseBackupService.shared.restoreFromBackup(context: context)
                    restoreSuccessMessage = "Данные восстановлены из облака"
                } catch {
                    restoreError = error.localizedDescription
                }
                isRestoring = false
            }
        case .exportCloud:
            Task {
                isRestoring = true
                do {
                    try await FirebaseBackupService.shared.forceExport(context: context)
                    restoreSuccessMessage = "Данные сохранены в облако"
                } catch {
                    restoreError = error.localizedDescription
                }
                isRestoring = false
            }
        case .importFile:
            guard let url = pendingBackupURL else { return }
            Task {
                isRestoring = true
                do {
                    try await FirebaseBackupService.shared.restoreFromBackupFile(url: url, context: context)
                    restoreSuccessMessage = "Данные восстановлены из файла"
                } catch {
                    restoreError = error.localizedDescription
                }
                isRestoring = false
                pendingBackupURL = nil
            }
        case .exportHome:
            Task {
                isRestoring = true
                do {
                    try await HomeBackupService.shared.forceHomeExport(context: context)
                    homeLastSuccessTick += 1
                    restoreSuccessMessage = "Данные сохранены на Raspberry Pi"
                } catch {
                    restoreError = error.localizedDescription
                }
                isRestoring = false
            }
        }
        if action != .restore && action != .exportCloud && action != .importFile && action != .exportHome {
            try? context.save()
        }
    }
    private func bmiColor(_ bmi: Double) -> Color {
        switch bmi {
        case ..<18.5: return Color(hex: "#5b8cff")
        case 18.5..<25: return Color(hex: "#3aff9e")
        case 25..<30: return Color(hex: "#ffb830")
        default: return Color(hex: "#ff5c3a")
        }
    }
}

struct BodyProfileEditView: View {
    @Bindable var profile: BodyProfile
    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""; @State private var heightText = ""
    @State private var ageText = ""; @State private var hrText = ""; @State private var fatText = ""
    @State private var targetWeightText = ""
    @State private var showFat = false
    /// true = ввод возраста вручную, false = дата рождения (возраст считается сам)
    @State private var useBirthDate = false
    @State private var birthDatePicker = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                Form {
                    Section("Основное") {
                        field("Вес (кг)", text: $weightText, keyboard: .decimalPad)
                        field("Рост (см)", text: $heightText, keyboard: .decimalPad)
                        Picker("Пол", selection: $profile.gender) {
                            ForEach(Gender.allCases, id: \.self) { g in
                                Text(g.title).tag(g)
                            }
                        }
                    }
                    Section("Возраст") {
                        Picker("Способ", selection: $useBirthDate) {
                            Text("Возраст (лет)").tag(false)
                            Text("Дата рождения").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if useBirthDate {
                            DatePicker("Дата рождения", selection: $birthDatePicker, displayedComponents: .date)
                                .environment(\.locale, Locale(identifier: "ru_RU"))
                        } else {
                            field("Лет", text: $ageText, keyboard: .numberPad)
                        }
                    }
                    Section("Цель") {
                        Picker("Цель", selection: Binding(
                            get: { profile.goalRaw },
                            set: { profile.goalRaw = $0 }
                        )) {
                            Text("Не выбрано").tag("")
                            ForEach(BodyGoal.allCases, id: \.rawValue) { g in
                                Text(g.title).tag(g.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        field("Целевой вес (кг)", text: $targetWeightText, keyboard: .decimalPad)
                        if profile.suggestedTargetWeight != nil, targetWeightText.isEmpty {
                            Text("Оставь пустым — цель подставится по выбранной цели и росту")
                                .font(.caption).foregroundStyle(Color(hex: "#6b6b80"))
                        }
                    }
                    Section("Активность") {
                        Picker("Уровень", selection: $profile.activityLevel) {
                            Text("Сидячий (1.2)").tag(1.2)
                            Text("Низкий (1.375)").tag(1.375)
                            Text("Умеренный (1.55)").tag(1.55)
                            Text("Высокий (1.725)").tag(1.725)
                            Text("Экстремальный (1.9)").tag(1.9)
                        }
                    }
                    Section("Сердечно-сосудистая") {
                        field("ЧСС покоя (уд/мин)", text: $hrText, keyboard: .numberPad)
                    }
                    Section("Дополнительно") {
                        Toggle("Указать % жира", isOn: $showFat)
                        if showFat { field("% жира", text: $fatText, keyboard: .decimalPad) }
                    }
                }
                .dismissKeyboardOnTap()
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() }.foregroundStyle(Color(hex: "#6b6b80")) }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save(); dismiss() }.foregroundStyle(Color(hex: "#ff5c3a")).fontWeight(.semibold) }
            }
            .onAppear {
                weightText = profile.weight > 0 ? String(format: "%.1f", profile.weight) : ""
                heightText = profile.height > 0 ? String(format: "%.0f", profile.height) : ""
                if let d = profile.birthDate {
                    useBirthDate = true
                    birthDatePicker = d
                    ageText = ""
                } else {
                    useBirthDate = false
                    ageText = profile.age > 0 ? "\(profile.age)" : ""
                    birthDatePicker = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
                }
                hrText = profile.restingHeartRate > 0 ? "\(profile.restingHeartRate)" : ""
                targetWeightText = profile.targetWeightKg > 0 ? String(format: "%.1f", profile.targetWeightKg) : ""
                if let f = profile.bodyFatPercent { fatText = String(format: "%.1f", f); showFat = true }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text).keyboardType(keyboard).multilineTextAlignment(.trailing).frame(width: 80)
        }
    }

    private func save() {
        let fix = { (s: String) in s.replacingOccurrences(of: ",", with: ".") }
        if let w = Double(fix(weightText)) {
            let oldWeight = profile.weight
            profile.weight = w
            if w != oldWeight && profile.healthKitEnabled {
                Task { await HealthKitManager.shared.saveWeight(w, date: Date()) }
            }
        }
        if let h = Double(fix(heightText)) { profile.height = h }
        if useBirthDate {
            profile.birthDate = birthDatePicker
            profile.age = 0
        } else {
            profile.birthDate = nil
            if let a = Int(ageText) { profile.age = a }
        }
        if let hr = Int(hrText) { profile.restingHeartRate = hr }
        profile.targetWeightKg = Double(fix(targetWeightText)) ?? 0
        profile.bodyFatPercent = showFat ? Double(fix(fatText)) : nil
        profile.updatedAt = Date()
    }
}
