import SwiftUI
import SwiftData
import UIKit

// MARK: - Root overlay

struct GymBroOverlay: View {
    @Environment(\.modelContext) private var context
    @Environment(GymBroManager.self) private var manager
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @Query(sort: \WorkoutTemplate.createdAt, order: .reverse) private var templates: [WorkoutTemplate]
    @Query private var profiles: [BodyProfile]

    private var profile: BodyProfile? { profiles.first }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if !manager.isOpen {
                GymBroFAB(manager: manager, workouts: workouts, templates: templates, profile: profile)
                    .padding(.trailing, 20)
                    .padding(.bottom, 96)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.isOpen)
        .onAppear {
            manager.initialize(workouts: workouts, templates: templates, profile: profile, context: context)
            if NotificationDelegate.pendingGymBroOpen {
                NotificationDelegate.pendingGymBroOpen = false
                manager.open(workouts: workouts, templates: templates, profile: profile)
            }
        }
        .onChange(of: workouts.count) { _, _ in
            manager.refreshInsights(workouts: workouts, templates: templates, profile: profile)
        }
        .onChange(of: templates.count) { _, _ in
            manager.refreshInsights(workouts: workouts, templates: templates, profile: profile)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGymBroChat)) { _ in
            manager.open(workouts: workouts, templates: templates, profile: profile)
        }
        .fullScreenCover(isPresented: Binding(
            get: { manager.isOpen },
            set: { if !$0 { manager.close() } }
        )) {
            GymBroChatScreen(manager: manager, workouts: workouts, templates: templates)
        }
    }
}

// MARK: - FAB

struct GymBroFAB: View {
    var manager: GymBroManager
    let workouts: [Workout]
    var templates: [WorkoutTemplate] = []
    var profile: BodyProfile?
    @State private var glowScale: CGFloat = 1.0

    var body: some View {
        Button { withAnimation { manager.open(workouts: workouts, templates: templates, profile: profile) } } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#1a2040"), Color(hex: "#0e1030")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay(Circle().stroke(Color(hex: "#4a8cff").opacity(0.5), lineWidth: 1.5))
                    .shadow(color: Color(hex: "#4a8cff").opacity(0.35 * glowScale), radius: 12 * glowScale)
                    .shadow(color: Color(hex: "#4a8cff").opacity(0.15), radius: 24)

                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "#4a8cff"), Color(hex: "#8bb8ff")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )

                if manager.hasUnread {
                    let count = manager.insights.filter { $0.severity == .alert || $0.severity == .warn }.count
                    if count > 0 {
                        Circle()
                            .fill(Color(hex: "#ff4a2a"))
                            .frame(width: 16, height: 16)
                            .overlay(
                                Text("\(count)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                            .overlay(Circle().stroke(Color(hex: "#09090f"), lineWidth: 2))
                            .offset(x: 18, y: -18)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                glowScale = 1.6
            }
        }
    }
}

// MARK: - Full-screen chat

struct GymBroChatScreen: View {
    var manager: GymBroManager
    let workouts: [Workout]
    var templates: [WorkoutTemplate] = []
    @Query private var profiles: [BodyProfile]

    private var profile: BodyProfile? { profiles.first }

    @State private var inputText = ""
    @State private var attachedWorkouts: [Workout] = []
    @State private var attachedTemplates: [WorkoutTemplate] = []
    @State private var attachedImages: [(id: UUID, data: Data)] = []
    @State private var showAttachmentPicker = false
    @State private var showPhotoPicker = false
    @State private var isAtBottom = true
    @State private var showChatList = false
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var hasAttachments: Bool {
        !attachedWorkouts.isEmpty || !attachedTemplates.isEmpty || !attachedImages.isEmpty
    }
    private var totalAttachments: Int {
        attachedWorkouts.count + attachedTemplates.count + attachedImages.count
    }
    private var attachedImagesData: [Data] { attachedImages.map(\.data) }

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            insightChips
            if manager.screenContextImage != nil {
                HStack(spacing: 6) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#4a8cff"))
                    Text("Фото упражнения будет отправлено с сообщением")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }
            messagesArea
            if !isInputFocused { quickAsks }
            if hasAttachments { attachedChips }
            inputRow
        }
        .dismissKeyboardOnTap()
        .background(Color(hex: "#111118").ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAttachmentPicker) {
            AttachmentPickerSheet(
                workouts: workouts,
                templates: templates,
                selectedWorkouts: $attachedWorkouts,
                selectedTemplates: $attachedTemplates
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showChatList) {
            ChatListSheet(
                manager: manager,
                workouts: workouts,
                templates: templates,
                profile: profile
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPhotoPicker) {
            ChatPhotoPickerSheet(selectedImages: $attachedImages)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack(spacing: 10) {
            Button { showChatList = true } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(LinearGradient(colors: [Color(hex: "#1a2040"), Color(hex: "#0e1030")], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 42, height: 42)
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(hex: "#4a8cff").opacity(0.4), lineWidth: 1.5))
                        .shadow(color: Color(hex: "#4a8cff").opacity(0.2), radius: 8)
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(hex: "#4a8cff"))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(manager.chatTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "#eeeef5"))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: "#1effa0")).frame(width: 6, height: 6)
                    Text("Life Bro · Gemini")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "#55556a"))
                }
            }

            Spacer()

            Button {
                manager.createNewChat(workouts: workouts, templates: templates, profile: profile)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: "#4a8cff"))
                    .frame(width: 30, height: 30)
                    .background(Color(hex: "#4a8cff").opacity(0.1))
                    .clipShape(Circle())
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "#55556a"))
                    .frame(width: 30, height: 30)
                    .background(Color(hex: "#18181f"))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "#111118"))
        .overlay(Divider().background(Color(hex: "#55556a").opacity(0.2)), alignment: .bottom)
    }

    // MARK: - Insight chips

    private var insightChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(manager.insights) { chip in
                    Button {
                        inputText = chip.label + " — " + chip.value
                        sendMessage()
                    } label: {
                        HStack(spacing: 7) {
                            Text(chip.icon).font(.system(size: 15))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(chip.label)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(chipColor(chip.severity))
                                Text(chip.value)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(hex: "#55556a"))
                            }
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(Color(hex: "#18181f"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#55556a").opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func chipColor(_ severity: GymBroInsight.Severity) -> Color {
        switch severity {
        case .good:  return Color(hex: "#1effa0")
        case .warn:  return Color(hex: "#ffb020")
        case .alert: return Color(hex: "#ff4a2a")
        }
    }

    // MARK: - Messages

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(manager.messages) { msg in
                            VStack(spacing: 8) {
                                MessageRow(message: msg)
                                if let template = msg.template {
                                    TemplateCard(
                                        template: template,
                                        messageId: msg.id,
                                        manager: manager
                                    )
                                    .padding(.horizontal, 14)
                                }
                                if let action = msg.lifeAction {
                                    LifeActionCard(
                                        action: action,
                                        messageId: msg.id,
                                        manager: manager
                                    )
                                    .padding(.horizontal, 14)
                                }
                            }
                            .id(msg.id.uuidString)
                        }

                        if manager.isLoading || !manager.streamingText.isEmpty {
                            HStack(alignment: .bottom, spacing: 9) {
                                aiAvatar
                                VStack(alignment: .leading, spacing: 4) {
                                    if manager.streamingText.isEmpty {
                                        typingBubble
                                    } else {
                                        markdownView(manager.streamingText)
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color(hex: "#eeeef5"))
                                            .lineSpacing(3)
                                            .padding(.horizontal, 13)
                                            .padding(.vertical, 10)
                                            .background(Color(hex: "#18181f"))
                                            .clipShape(UnevenRoundedRectangle(
                                                topLeadingRadius: 4, bottomLeadingRadius: 14,
                                                bottomTrailingRadius: 14, topTrailingRadius: 14
                                            ))
                                    }
                                    if manager.loadingLongWait {
                                        Text("ИИ думает…")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color(hex: "#6b6b80"))
                                    }
                                }
                                Spacer(minLength: 40)
                            }
                            .padding(.horizontal, 14)
                            .id("typing")
                        }

                        if let err = manager.errorMessage {
                            VStack(spacing: 8) {
                                Text(err)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(hex: "#ff4a2a"))
                                Button {
                                    manager.retry(workouts: workouts, templates: templates, profile: profile)
                                } label: {
                                    Text("Повторить")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color(hex: "#4a8cff"))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                        .background(Color(hex: "#4a8cff").opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .id("error")
                        }

                        Color.clear.frame(height: 1).id("bottom")
                            .onAppear { isAtBottom = true }
                            .onDisappear { isAtBottom = false }
                    }
                    .padding(.vertical, 10)
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture { isInputFocused = false }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: manager.currentChatId) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: manager.messages.count) { _, _ in
                    // Задержка ~0.15 — дать LazyVStack отрендерить новую ячейку, иначе скролл «прыгает»
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: manager.isLoading) { _, loading in
                    if loading {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: manager.streamingText) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                // Не скроллить при фокусе на поле ввода: клавиатура меняет layout, scrollTo даёт сбой и сообщения «пропадают»

                if !isAtBottom {
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("bottom")
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: "#eeeef5"))
                            .frame(width: 36, height: 36)
                            .background(Color(hex: "#1a1a24"))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color(hex: "#55556a").opacity(0.3), lineWidth: 1))
                            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 14)
                    .padding(.bottom, 10)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private var aiAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [Color(hex: "#1a2040"), Color(hex: "#0e1030")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: "#4a8cff").opacity(0.3), lineWidth: 1))
            Text("🤖").font(.system(size: 14))
        }
    }

    private var typingBubble: some View {
        TypingDotsView()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(hex: "#18181f"))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#55556a").opacity(0.15), lineWidth: 1))
    }

    // MARK: - Quick asks

    private var quickAsks: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(quickQuestions, id: \.self) { q in
                    Button {
                        inputText = q
                        sendMessage()
                    } label: {
                        Text(q)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "#4a8cff"))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(Color(hex: "#18181f"))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color(hex: "#55556a").opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private let quickQuestions = [
        "Что съесть после тренировки?",
        "Как убрать дисбаланс мышц?",
        "Что такое deload?",
        "Сколько спать для роста?",
        "Как прогрессировать в жиме?",
    ]

    // MARK: - Attached chips

    private var attachedChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachedWorkouts, id: \.id) { w in
                    let df = { () -> DateFormatter in let f = DateFormatter(); f.dateFormat = "dd.MM"; return f }()
                    attachmentChip(
                        icon: "dumbbell.fill",
                        label: "\(df.string(from: w.date)) \(w.name)",
                        color: Color(hex: "#4a8cff")
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            attachedWorkouts.removeAll { $0.id == w.id }
                        }
                    }
                }
                ForEach(attachedTemplates, id: \.id) { t in
                    attachmentChip(
                        icon: "doc.text.fill",
                        label: t.name,
                        color: Color(hex: "#ffb020")
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            attachedTemplates.removeAll { $0.id == t.id }
                        }
                    }
                }
                ForEach(attachedImages, id: \.id) { item in
                    if let uiImage = UIImage(data: item.data) {
                        imageAttachmentChip(uiImage: uiImage) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                attachedImages.removeAll { $0.id == item.id }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func attachmentChip(icon: String, label: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: "#eeeef5"))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(hex: "#55556a"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
    }

    private func imageAttachmentChip(uiImage: UIImage, onRemove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#55556a").opacity(0.3), lineWidth: 1))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            .offset(x: 4, y: -4)
        }
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(spacing: 8) {
            Button {
                showAttachmentPicker = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(!hasAttachments ? Color(hex: "#55556a") : Color(hex: "#4a8cff"))
                        .frame(width: 36, height: 36)

                    if hasAttachments {
                        Text("\(totalAttachments)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 15, height: 15)
                            .background(Color(hex: "#4a8cff"))
                            .clipShape(Circle())
                            .offset(x: 3, y: -1)
                    }
                }
            }

            Button {
                showPhotoPicker = true
            } label: {
                Image(systemName: "photo")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(attachedImages.isEmpty ? Color(hex: "#55556a") : Color(hex: "#4a8cff"))
                    .frame(width: 36, height: 36)
            }

            if isInputFocused {
                Button {
                    isInputFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "#55556a"))
                }
                .transition(.scale.combined(with: .opacity))
            }

            TextField("Спроси что угодно...", text: $inputText, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#eeeef5"))
                .lineLimit(1...4)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: "#18181f"))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(
                            isInputFocused ? Color(hex: "#4a8cff").opacity(0.4) : Color(hex: "#55556a").opacity(0.2),
                            lineWidth: 1
                        )
                )
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isLoading
                            ? Color(hex: "#55556a")
                            : Color(hex: "#4a8cff")
                    )
                    .clipShape(Circle())
                    .shadow(color: Color(hex: "#4a8cff").opacity(inputText.isEmpty ? 0 : 0.4), radius: 8)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isLoading)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color(hex: "#111118"))
        .overlay(Divider().background(Color(hex: "#55556a").opacity(0.15)), alignment: .top)
        .animation(.easeOut(duration: 0.2), value: isInputFocused)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let attached = attachedWorkouts
        let attachedTmpls = attachedTemplates
        let images = attachedImagesData
        inputText = ""
        attachedWorkouts = []
        attachedTemplates = []
        attachedImages = []
        manager.send(text: text, workouts: workouts, templates: templates, profile: profile, attached: attached, attachedTemplates: attachedTmpls, attachedImages: images)
    }
}

// MARK: - Typing Dots

private struct TypingDotsView: View {
    @State private var active = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color(hex: "#4a8cff"))
                    .frame(width: 6, height: 6)
                    .opacity(active ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.15),
                        value: active
                    )
            }
        }
        .onAppear { active = true }
    }
}

// MARK: - Markdown

/// View с рендерингом markdown (**жирный**, *курсив*) через AttributedString или fallback.
/// inlineOnlyPreservingWhitespace уменьшает падения на заголовках (#) и некорректном markdown от Gemini.
private func markdownView(_ s: String) -> some View {
    if let attr = try? AttributedString(markdown: s, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
        return AnyView(Text(attr))
    }
    return AnyView(markdownText(s))
}

/// Fallback: **жирный** и *курсив* (когда AttributedString не подходит).
private func markdownText(_ s: String) -> Text {
    let parts = s.split(separator: "**", omittingEmptySubsequences: false).map(String.init)
    guard !parts.isEmpty else { return Text(verbatim: "") }
    var result = Text(verbatim: "")
    for (i, part) in parts.enumerated() {
        let segment = i % 2 == 1 ? Text(verbatim: part).bold() : inlineFormatted(part)
        result = Text("\(result)\(segment)")
    }
    return result
}

private func inlineFormatted(_ s: String) -> Text {
    let parts = s.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
    guard parts.count > 1 else { return Text(verbatim: s) }
    var result = Text(verbatim: parts[0])
    for i in 1..<parts.count {
        let next = i % 2 == 1 ? Text(verbatim: parts[i]).italic() : Text(verbatim: parts[i])
        result = Text("\(result)\(next)")
    }
    return result
}

// MARK: - Message Row

struct MessageRow: View {
    let message: GymBroMessage

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "ru_RU")
        return f
    }()

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            if message.role == .ai {
                aiAvatar
                aiBubble
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                userBubble
                userAvatar
            }
        }
        .padding(.horizontal, 14)
    }

    private var aiAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [Color(hex: "#1a2040"), Color(hex: "#0e1030")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: "#4a8cff").opacity(0.3), lineWidth: 1))
            Text("🤖").font(.system(size: 14))
        }
    }

    private var userAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [Color(hex: "#2a1010"), Color(hex: "#1a0808")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: "#ff4a2a").opacity(0.3), lineWidth: 1))
            Text("👤").font(.system(size: 14))
        }
    }

    private var aiBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            markdownView(message.text)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#eeeef5"))
                .lineSpacing(3)
            messageTimestamp
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Color(hex: "#18181f"))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 4, bottomLeadingRadius: 14,
                bottomTrailingRadius: 14, topTrailingRadius: 14
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 4, bottomLeadingRadius: 14,
                bottomTrailingRadius: 14, topTrailingRadius: 14
            )
            .stroke(Color(hex: "#55556a").opacity(0.15), lineWidth: 1)
        )
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.text
            } label: {
                Label("Копировать", systemImage: "doc.on.doc")
            }
        }
    }

    private var messageTimestamp: some View {
        Text(MessageRow.timeFormatter.string(from: message.timestamp))
            .font(.system(size: 10))
            .foregroundStyle(Color(hex: "#6b6b80"))
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !message.attachedImageData.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(message.attachedImageData.enumerated()), id: \.offset) { _, data in
                        if let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            markdownView(message.text)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#eeeef5"))
                .lineSpacing(3)
            messageTimestamp
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Color(hex: "#ff4a2a").opacity(0.13))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 14, bottomLeadingRadius: 14,
                bottomTrailingRadius: 4, topTrailingRadius: 14
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 14, bottomLeadingRadius: 14,
                bottomTrailingRadius: 4, topTrailingRadius: 14
            )
            .stroke(Color(hex: "#ff4a2a").opacity(0.2), lineWidth: 1)
        )
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.text
            } label: {
                Label("Копировать", systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK: - Template Card

struct TemplateCard: View {
    let template: PendingTemplate
    let messageId: UUID
    var manager: GymBroManager
    @Environment(\.modelContext) private var context
    @State private var saved = false

    private var isEdit: Bool { template.existingId != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isEdit ? "pencil.and.outline" : "doc.on.doc.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(isEdit ? Color(hex: "#ffb020") : Color(hex: "#4a8cff"))

                if isEdit {
                    Text("Редактирование")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "#ffb020"))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color(hex: "#ffb020").opacity(0.15))
                        .clipShape(Capsule())
                }

                Text(template.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: "#eeeef5"))
                    .lineLimit(1)
                Spacer()
                Text("\(template.exercises.count) упр.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#55556a"))
            }

            ForEach(Array(template.exercises.enumerated()), id: \.offset) { idx, ex in
                HStack(spacing: 8) {
                    Text("\(idx + 1)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "#4a8cff"))
                        .frame(width: 18, height: 18)
                        .background(Color(hex: "#4a8cff").opacity(0.15))
                        .clipShape(Circle())

                    Text(ex.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: "#eeeef5"))

                    Spacer()

                    Text("\(ex.sets)×\(ex.reps)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(hex: "#55556a"))

                    if ex.weight > 0 {
                        Text("\(ex.weight, specifier: "%.0f")кг")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                    }
                }
            }

            let totalSets = template.exercises.reduce(0) { $0 + $1.sets }

            Divider().background(Color(hex: "#55556a").opacity(0.2))

            if saved || template.isSaved {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: "#3aff9e"))
                    Text(isEdit ? "Шаблон обновлён" : "Сохранено в шаблоны")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "#3aff9e"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            } else {
                Button {
                    saveTemplate()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isEdit ? "arrow.triangle.2.circlepath" : "square.and.arrow.down.fill")
                            .font(.system(size: 13))
                        Text(isEdit ? "Применить изменения" : "Сохранить в шаблоны")
                            .font(.system(size: 13, weight: .bold))
                        Text("· \(totalSets) сетов")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#55556a"))
                    }
                    .foregroundStyle(isEdit ? Color(hex: "#ffb020") : Color(hex: "#4a8cff"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background((isEdit ? Color(hex: "#ffb020") : Color(hex: "#4a8cff")).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke((isEdit ? Color(hex: "#ffb020") : Color(hex: "#4a8cff")).opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(hex: "#18181f"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke((isEdit ? Color(hex: "#ffb020") : Color(hex: "#4a8cff")).opacity(0.2), lineWidth: 1)
        )
    }

    private func saveTemplate() {
        if let existingId = template.existingId {
            let descriptor = FetchDescriptor<WorkoutTemplate>()
            if let existing = (try? context.fetch(descriptor))?.first(where: { $0.id == existingId }) {
                existing.name = template.name
                for ex in existing.exercises { context.delete(ex) }
                existing.exercises = []
                for (i, ex) in template.exercises.enumerated() {
                    let te = TemplateExercise(
                        order: i,
                        exerciseName: ex.name,
                        bodyPart: ex.bodyPart,
                        timerSeconds: ex.timerSeconds,
                        defaultSets: ex.sets,
                        defaultReps: ex.reps,
                        defaultWeight: ex.weight
                    )
                    existing.exercises.append(te)
                }
                try? context.save()
                saved = true
                manager.markTemplateSaved(messageId: messageId)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                return
            }
        }

        let wt = WorkoutTemplate(name: template.name)
        for (i, ex) in template.exercises.enumerated() {
            let te = TemplateExercise(
                order: i,
                exerciseName: ex.name,
                bodyPart: ex.bodyPart,
                timerSeconds: ex.timerSeconds,
                defaultSets: ex.sets,
                defaultReps: ex.reps,
                defaultWeight: ex.weight
            )
            wt.exercises.append(te)
        }
        context.insert(wt)
        try? context.save()
        saved = true
        manager.markTemplateSaved(messageId: messageId)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Chat List Sheet

struct ChatListSheet: View {
    var manager: GymBroManager
    let workouts: [Workout]
    var templates: [WorkoutTemplate] = []
    var profile: BodyProfile?
    @Query(sort: \GymBroChat.updatedAt, order: .reverse) private var chats: [GymBroChat]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Button {
                    manager.createNewChat(workouts: workouts, templates: templates, profile: profile)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(hex: "#4a8cff"))
                        Text("Новый чат")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: "#eeeef5"))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(hex: "#4a8cff").opacity(0.08))
                }
                .buttonStyle(.plain)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(chats, id: \.id) { chat in
                            chatRow(chat)
                        }
                    }
                }
            }
            .background(Color(hex: "#111118"))
            .navigationTitle("Чаты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "#4a8cff"))
                }
            }
            .toolbarBackground(Color(hex: "#111118"), for: .navigationBar)
            .preferredColorScheme(.dark)
        }
    }

    private func chatRow(_ chat: GymBroChat) -> some View {
        let isCurrent = chat.id == manager.currentChatId
        let lastMsg = chat.messages.sorted { $0.timestamp < $1.timestamp }.last
        let df = RelativeDateTimeFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.unitsStyle = .abbreviated
        let timeStr = df.localizedString(for: chat.updatedAt, relativeTo: Date())
        let msgCount = chat.messages.filter { !$0.isSetComment }.count

        return Button {
            manager.switchToChat(chat.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isCurrent
                              ? Color(hex: "#4a8cff").opacity(0.2)
                              : Color(hex: "#18181f"))
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isCurrent ? Color(hex: "#4a8cff").opacity(0.5) : Color(hex: "#55556a").opacity(0.2), lineWidth: 1)
                        )
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(isCurrent ? Color(hex: "#4a8cff") : Color(hex: "#55556a"))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(chat.title)
                            .font(.system(size: 14, weight: isCurrent ? .bold : .semibold))
                            .foregroundStyle(Color(hex: "#eeeef5"))
                            .lineLimit(1)
                        Spacer()
                        Text(timeStr)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#55556a"))
                    }

                    HStack(spacing: 6) {
                        Text("\(msgCount) сообщ.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#55556a"))
                        if let lastMsg {
                            Text("· " + lastMsg.text.prefix(50))
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: "#55556a").opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isCurrent ? Color(hex: "#4a8cff").opacity(0.04) : Color.clear)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation { manager.deleteChat(chat.id) }
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }
}

// MARK: - Chat Photo Picker Sheet (добавление фото в чат Life Bro)

struct ChatPhotoPickerSheet: View {
    @Binding var selectedImages: [(id: UUID, data: Data)]
    @Environment(\.dismiss) private var dismiss
    @State private var showImagePicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if selectedImages.isEmpty {
                    Text("Добавь фото — Life Bro учтёт их в ответе")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                        .padding(.vertical, 24)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedImages, id: \.id) { item in
                                ZStack(alignment: .topTrailing) {
                                    if let uiImage = UIImage(data: item.data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    Button {
                                        selectedImages = selectedImages.filter { $0.id != item.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(.white)
                                            .shadow(radius: 2)
                                    }
                                    .offset(x: 6, y: -6)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 12)
                }
                Button {
                    showImagePicker = true
                } label: {
                    Label("Добавить фото", systemImage: "photo.badge.plus")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "#4a8cff").opacity(0.2))
                        .foregroundStyle(Color(hex: "#4a8cff"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                Spacer(minLength: 0)
            }
            .background(Color(hex: "#111118"))
            .navigationTitle("Фото в чат")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(Color(hex: "#4a8cff"))
                }
            }
            .fullScreenCover(isPresented: $showImagePicker) {
                ChatImagePickerView(
                    onPick: { data in
                        selectedImages = selectedImages + [(id: UUID(), data: data)]
                        showImagePicker = false
                    },
                    onDismiss: { showImagePicker = false }
                )
            }
        }
    }
}

private struct ChatImagePickerView: UIViewControllerRepresentable {
    var onPick: (Data) -> Void
    var onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ChatImagePickerView
        init(_ parent: ChatImagePickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                parent.onPick(data)
            }
            parent.onDismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onDismiss()
        }
    }
}

// MARK: - Attachment Picker Sheet

struct AttachmentPickerSheet: View {
    let workouts: [Workout]
    let templates: [WorkoutTemplate]
    @Binding var selectedWorkouts: [Workout]
    @Binding var selectedTemplates: [WorkoutTemplate]
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    private var finished: [Workout] {
        workouts.filter { $0.finishedAt != nil }
    }

    private var totalSelected: Int {
        selectedWorkouts.count + selectedTemplates.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Тренировки").tag(0)
                    Text("Шаблоны").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if totalSelected > 0 {
                    HStack {
                        Text("\(totalSelected) выбрано")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "#4a8cff"))
                        Spacer()
                        Button("Очистить") {
                            selectedWorkouts.removeAll()
                            selectedTemplates.removeAll()
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: "#4a8cff").opacity(0.08))
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if tab == 0 {
                            if finished.isEmpty {
                                emptyState(icon: "dumbbell", text: "Нет завершённых тренировок")
                            } else {
                                ForEach(finished, id: \.id) { w in
                                    workoutRow(w)
                                }
                            }
                        } else {
                            if templates.isEmpty {
                                emptyState(icon: "doc.text", text: "Нет сохранённых шаблонов")
                            } else {
                                ForEach(templates, id: \.id) { t in
                                    templateRow(t)
                                }
                            }
                        }
                    }
                }
            }
            .background(Color(hex: "#111118"))
            .navigationTitle("Прикрепить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "#4a8cff"))
                }
            }
            .toolbarBackground(Color(hex: "#111118"), for: .navigationBar)
            .preferredColorScheme(.dark)
        }
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Color(hex: "#55556a").opacity(0.5))
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#55556a"))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Workout row

    private func isWorkoutSelected(_ w: Workout) -> Bool {
        selectedWorkouts.contains { $0.id == w.id }
    }

    private func toggleWorkout(_ w: Workout) {
        if let idx = selectedWorkouts.firstIndex(where: { $0.id == w.id }) {
            selectedWorkouts.remove(at: idx)
        } else {
            selectedWorkouts.append(w)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func workoutRow(_ w: Workout) -> some View {
        let df = { () -> DateFormatter in
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateFormat = "d MMM, EE"
            return f
        }()
        let sel = isWorkoutSelected(w)
        let exerciseNames = w.workoutExercises
            .sorted { $0.order < $1.order }
            .prefix(3)
            .map { $0.exercise.name }
        let setsCount = w.workoutExercises.reduce(0) { $0 + $1.workoutSets.filter(\.isCompleted).count }

        return Button { toggleWorkout(w) } label: {
            HStack(spacing: 12) {
                checkboxView(selected: sel)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: "#4a8cff"))
                        Text(w.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: "#eeeef5"))
                            .lineLimit(1)
                        Spacer()
                        Text(df.string(from: w.date))
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#55556a"))
                    }

                    HStack(spacing: 8) {
                        if let dur = w.durationFormatted {
                            Label(dur, systemImage: "clock")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: "#55556a"))
                        }
                        Text("\(setsCount) сетов")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#55556a"))
                        Text(exerciseNames.joined(separator: ", ") + (w.workoutExercises.count > 3 ? "…" : ""))
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#55556a").opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(sel ? Color(hex: "#4a8cff").opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Template row

    private func isTemplateSelected(_ t: WorkoutTemplate) -> Bool {
        selectedTemplates.contains { $0.id == t.id }
    }

    private func toggleTemplate(_ t: WorkoutTemplate) {
        if let idx = selectedTemplates.firstIndex(where: { $0.id == t.id }) {
            selectedTemplates.remove(at: idx)
        } else {
            selectedTemplates.append(t)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func templateRow(_ t: WorkoutTemplate) -> some View {
        let sel = isTemplateSelected(t)
        let exerciseNames = t.exercises
            .sorted { $0.order < $1.order }
            .prefix(3)
            .map { $0.exerciseName }
        let totalExercises = t.exercises.count

        return Button { toggleTemplate(t) } label: {
            HStack(spacing: 12) {
                checkboxView(selected: sel)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: "#ffb020"))
                        Text(t.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: "#eeeef5"))
                            .lineLimit(1)
                        Spacer()
                        Text("\(totalExercises) упр.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#55556a"))
                    }

                    Text(exerciseNames.joined(separator: ", ") + (totalExercises > 3 ? "…" : ""))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#55556a").opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(sel ? Color(hex: "#ffb020").opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func checkboxView(selected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color(hex: "#4a8cff") : Color(hex: "#18181f"))
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? Color.clear : Color(hex: "#55556a").opacity(0.4), lineWidth: 1)
                )
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Life Action Card

struct LifeActionCard: View {
    let action: PendingLifeAction
    let messageId: UUID
    var manager: GymBroManager
    @Environment(\.modelContext) private var context
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#a855f7"))

                Text("Life Bro предлагает")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: "#a855f7"))
                Spacer()
                Text("\(action.itemCount) шт.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#55556a"))
            }

            if !action.habits.isEmpty {
                Text("ПРИВЫЧКИ")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(hex: "#55556a"))
                    .tracking(1)

                ForEach(Array(action.habits.enumerated()), id: \.offset) { _, h in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: h.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(Color(hex: h.colorHex))
                                .frame(width: 20)
                            Text(h.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(hex: "#eeeef5"))
                            if !h.todos.isEmpty {
                                Text("\(h.todos.count) шагов")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(hex: "#55556a"))
                            }
                        }
                        if !h.todos.isEmpty {
                            ForEach(Array(h.todos.enumerated()), id: \.offset) { _, todoTitle in
                                HStack(spacing: 6) {
                                    Image(systemName: "square")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(hex: h.colorHex).opacity(0.5))
                                    Text(todoTitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color(hex: "#9999aa"))
                                }
                                .padding(.leading, 28)
                            }
                        }
                    }
                }
            }

            if !action.todos.isEmpty {
                Text("ЗАДАЧИ")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(hex: "#55556a"))
                    .tracking(1)

                ForEach(Array(action.todos.enumerated()), id: \.offset) { _, t in
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(priorityColor(t.priority))
                            .frame(width: 20)
                        Text(t.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: "#eeeef5"))
                        if t.priority > 0 {
                            Text(t.priority == 2 ? "!!!" : "!!")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(priorityColor(t.priority))
                        }
                    }
                }
            }

            if !action.goals.isEmpty {
                Text("ЦЕЛИ НЕДЕЛИ")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(hex: "#55556a"))
                    .tracking(1)

                ForEach(Array(action.goals.enumerated()), id: \.offset) { _, g in
                    HStack(spacing: 8) {
                        Image(systemName: "target")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#ffb830"))
                            .frame(width: 20)
                        Text(g.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: "#eeeef5"))
                        Text((GoalPeriod(rawValue: g.period) ?? .week).label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(hex: "#55556a"))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(hex: "#1a1a24"))
                            .clipShape(Capsule())
                        Spacer()
                        Text("0/\(g.targetCount)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(hex: "#55556a"))
                    }
                }
            }

            Divider().background(Color(hex: "#55556a").opacity(0.2))

            if saved || action.isSaved {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: "#3aff9e"))
                    Text("Сохранено")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "#3aff9e"))
                }
                .frame(maxWidth: .infinity)
            } else {
                Button {
                    saveLifeAction()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                        Text("Добавить")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(hex: "#a855f7"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "#161620"))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: "#a855f7").opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 2: return Color(hex: "#ff5c3a")
        case 1: return Color(hex: "#ffb830")
        default: return Color(hex: "#5b8cff")
        }
    }

    private func saveLifeAction() {
        for h in action.habits {
            let habit = Habit(name: h.name, icon: h.icon, colorHex: h.colorHex)
            context.insert(habit)
            for todoTitle in h.todos {
                let todo = TodoItem(title: todoTitle)
                todo.habit = habit
                context.insert(todo)
                habit.linkedTodos.append(todo)
            }
        }
        for t in action.todos {
            let todo = TodoItem(title: t.title, priority: t.priority)
            context.insert(todo)
        }
        for g in action.goals {
            let goal = WeeklyGoal(title: g.title, targetCount: g.targetCount, period: GoalPeriod(rawValue: g.period) ?? .week)
            context.insert(goal)
        }
        try? context.save()
        saved = true
        manager.markLifeActionSaved(messageId: messageId)
    }
}
