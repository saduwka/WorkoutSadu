import SwiftUI
import SwiftData

struct VoiceInputView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FinanceAccount.createdAt) private var accounts: [FinanceAccount]

    @State private var recognizer = SpeechRecognizer()
    @State private var parsed: [ParsedFinanceEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didParse = false
    @State private var permissionDenied = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var selectedAccountID: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        micButton
                        transcriptCard
                        if isLoading { loadingView }
                        if let err = errorMessage { errorView(err) }
                        if didParse && !parsed.isEmpty { resultsCard }
                        if didParse && !parsed.isEmpty && !accounts.isEmpty { voiceAccountPicker }
                        if didParse && !parsed.isEmpty && !accounts.isEmpty && selectedAccountID == nil {
                            Text("Выберите счёт для сохранения")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#ff5c3a"))
                        }
                        if didParse && !parsed.isEmpty && accounts.isEmpty {
                            Text("Создайте счёт в разделе «Финансы»")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                        }
                        if didParse && !parsed.isEmpty { saveButton }
                        if permissionDenied { permissionView }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("ГОЛОСОВОЙ ВВОД")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { recognizer.stopRecording(); dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Mic button

    private var micButton: some View {
        VStack(spacing: 16) {
            ZStack {
                if recognizer.isRecording {
                    Circle()
                        .fill(Color(hex: "#5b8cff").opacity(0.1))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseScale)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulseScale)

                    Circle()
                        .fill(Color(hex: "#5b8cff").opacity(0.15))
                        .frame(width: 100, height: 100)
                        .scaleEffect(pulseScale * 0.9)
                }

                Button {
                    if recognizer.isRecording {
                        recognizer.stopRecording()
                        if !recognizer.transcript.isEmpty {
                            Task { await parseTranscript() }
                        }
                    } else {
                        Task {
                            let ok = await recognizer.requestPermissions()
                            if ok {
                                permissionDenied = false
                                recognizer.startRecording()
                                pulseScale = 1.15
                            } else {
                                permissionDenied = true
                            }
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(recognizer.isRecording ? Color(hex: "#ff5c3a") : Color(hex: "#5b8cff"))
                            .frame(width: 72, height: 72)
                        Image(systemName: recognizer.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }

            Text(recognizer.isRecording
                 ? "Говорите..."
                 : (didParse ? "Нажмите для новой записи" : "Нажмите и говорите"))
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
        .padding(.top, 20)
    }

    // MARK: - Transcript

    private var transcriptCard: some View {
        Group {
            if !recognizer.transcript.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("РАСПОЗНАНО")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                        .tracking(1)
                    Text(recognizer.transcript)
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .darkCard()
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Color(hex: "#5b8cff"))
            Text("Анализирую...")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
        .padding(16)
        .darkCard()
    }

    // MARK: - Error

    private func errorView(_ msg: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: "#ff5c3a"))
            Text(msg).font(.system(size: 14)).foregroundStyle(Color(hex: "#f0f0f5"))
        }
        .padding(16)
        .darkCard()
    }

    // MARK: - Permission

    private var permissionView: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.slash.fill")
                .font(.title).foregroundStyle(Color(hex: "#ff5c3a"))
            Text("Нет доступа к микрофону")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(Color(hex: "#f0f0f5"))
            Text("Разрешите доступ в Настройках")
                .font(.system(size: 12)).foregroundStyle(Color(hex: "#6b6b80"))
        }
        .padding(20)
        .darkCard()
    }

    // MARK: - Results

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("НАЙДЕНО: \(parsed.count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)
                .padding(.horizontal, 16).padding(.top, 12)

            ForEach(parsed) { entry in
                HStack(spacing: 12) {
                    let cat = FinanceCategory(rawValue: entry.category) ?? .other
                    Image(systemName: cat.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: cat.color))
                        .frame(width: 32, height: 32)
                        .background(Color(hex: cat.color).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: "#f0f0f5"))
                        Text(entry.category)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                    }
                    Spacer()
                    Text("\(entry.type == "Доход" ? "+" : "-")\(entry.amount)")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(entry.type == "Доход" ? Color(hex: "#3aff9e") : Color(hex: "#f0f0f5"))
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .padding(.bottom, 8)
        .darkCard()
    }

    // MARK: - Account picker

    private var voiceAccountPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(accounts) { acc in
                    Button { selectedAccountID = acc.id } label: {
                        HStack(spacing: 6) {
                            Image(systemName: acc.icon).font(.system(size: 12))
                            Text(acc.name).font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(selectedAccountID == acc.id ? .white : Color(hex: "#6b6b80"))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(selectedAccountID == acc.id ? Color(hex: acc.colorHex) : Color(hex: "#1a1a24"))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Save

    private var canSaveVoice: Bool {
        !parsed.isEmpty && !accounts.isEmpty && selectedAccountID != nil
    }

    private var saveButton: some View {
        Button {
            guard canSaveVoice, let accountID = selectedAccountID else { return }
            for entry in parsed {
                let cat = FinanceCategory(rawValue: entry.category) ?? .other
                let type = FinanceType(rawValue: entry.type) ?? .expense
                let tx = FinanceTransaction(
                    name: entry.name,
                    amount: entry.amount,
                    category: cat,
                    type: type,
                    date: entry.date ?? Date(),
                    accountID: accountID
                )
                context.insert(tx)
            }
            try? context.save()
            dismiss()
        } label: {
            Text("Сохранить \(parsed.count) записей")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canSaveVoice ? Color(hex: "#ff5c3a") : Color(hex: "#6b6b80").opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!canSaveVoice)
    }

    // MARK: - Parse

    private func parseTranscript() async {
        isLoading = true
        errorMessage = nil
        do {
            parsed = try await FinanceAIService.shared.parse(text: recognizer.transcript)
            didParse = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
