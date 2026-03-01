import Foundation
import SwiftData
import FirebaseAI
import UserNotifications

// MARK: - Chat Session

@Model
final class GymBroChat {
    var id: UUID = UUID()
    var title: String = "Новый чат"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \PersistedMessage.chat)
    var messages: [PersistedMessage]

    init(title: String = "Новый чат") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.messages = []
    }
}

// MARK: - Persisted Message

@Model
final class PersistedMessage {
    var id: UUID = UUID()
    var roleRaw: String = "ai"
    var text: String = ""
    var timestamp: Date = Date()
    var isSetComment: Bool = false
    var chat: GymBroChat?

    init(role: GymBroMessage.Role, text: String, isSetComment: Bool = false) {
        self.id = UUID()
        self.roleRaw = role == .user ? "user" : "ai"
        self.text = text
        self.timestamp = Date()
        self.isSetComment = isSetComment
    }
}

// MARK: - Chat Message

struct GymBroMessage: Identifiable {
    let id: UUID
    let role: Role
    let text: String
    let template: PendingTemplate?
    let lifeAction: PendingLifeAction?
    let timestamp: Date
    let isSetComment: Bool

    enum Role { case ai, user }

    init(id: UUID = UUID(), role: Role, text: String, template: PendingTemplate? = nil, lifeAction: PendingLifeAction? = nil, isSetComment: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.template = template
        self.lifeAction = lifeAction
        self.timestamp = Date()
        self.isSetComment = isSetComment
    }
}

// MARK: - Pending Template (parsed from AI response)

struct PendingTemplate: Identifiable {
    let id = UUID()
    let existingId: UUID?
    let name: String
    let exercises: [PendingExercise]
    var isSaved = false

    init(existingId: UUID? = nil, name: String, exercises: [PendingExercise]) {
        self.existingId = existingId
        self.name = name
        self.exercises = exercises
    }
}

struct PendingExercise {
    let name: String
    let bodyPart: String
    let sets: Int
    let reps: Int
    let weight: Double
    let timerSeconds: Int?
}

// MARK: - Pending Life Action (parsed from AI response)

struct PendingLifeAction: Identifiable {
    let id = UUID()
    let habits: [PendingHabit]
    let todos: [PendingTodo]
    let goals: [PendingGoal]
    var isSaved = false

    var isEmpty: Bool { habits.isEmpty && todos.isEmpty && goals.isEmpty }
    var itemCount: Int { habits.count + todos.count + goals.count }
}

struct PendingHabit {
    let name: String
    let icon: String
    let colorHex: String
    let todos: [String]
}

struct PendingTodo {
    let title: String
    let priority: Int
}

struct PendingGoal {
    let title: String
    let targetCount: Int
    let period: String
}

// MARK: - Insight Chip

struct GymBroInsight: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    let severity: Severity

    enum Severity { case good, warn, alert }
}

// MARK: - Manager

@Observable
final class GymBroManager {

    var messages: [GymBroMessage] = []
    var insights: [GymBroInsight] = []
    var isLoading = false
    var hasUnread = true
    var isOpen = false
    var errorMessage: String? = nil
    var currentChatId: UUID? = nil
    var chatTitle: String = "Новый чат"
    var showChatList = false

    private var insightsReady = false
    private var lastSummary: WorkoutSummary?
    private var lastCommentDate: Date?
    private var modelContext: ModelContext?

    private var _commentModel: GenerativeModel?
    private var commentModel: GenerativeModel {
        if let m = _commentModel { return m }
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let m = ai.generativeModel(
            modelName: "gemini-2.5-flash-lite",
            generationConfig: GenerationConfig(temperature: 0.9, maxOutputTokens: 128)
        )
        _commentModel = m
        return m
    }

    // MARK: - Public

    func initialize(workouts: [Workout], templates: [WorkoutTemplate] = [], profile: BodyProfile?, context: ModelContext) {
        self.modelContext = context
        guard !insightsReady else { return }
        insightsReady = true
        migrateOrphanMessages()
        let summary = buildSummary(workouts: workouts, templates: templates, profile: profile)
        lastSummary = summary
        insights = buildInsights(summary: summary)
    }

    func refreshInsights(workouts: [Workout], templates: [WorkoutTemplate] = [], profile: BodyProfile?) {
        let summary = buildSummary(workouts: workouts, templates: templates, profile: profile)
        lastSummary = summary
        insights = buildInsights(summary: summary)
    }

    func open(workouts: [Workout], templates: [WorkoutTemplate] = [], profile: BodyProfile?) {
        isOpen = true
        hasUnread = false
        if currentChatId == nil {
            loadMostRecentChat(workouts: workouts, templates: templates, profile: profile)
        }
    }

    func close() { isOpen = false }

    func createNewChat(workouts: [Workout], templates: [WorkoutTemplate] = [], profile: BodyProfile?) {
        guard let ctx = modelContext, !isLoading else { return }
        let chat = GymBroChat()
        ctx.insert(chat)
        try? ctx.save()
        currentChatId = chat.id
        chatTitle = chat.title
        messages = []
        errorMessage = nil
        let summary = lastSummary ?? buildSummary(workouts: workouts, templates: templates, profile: profile)
        Task { await fetchOpeningMessage(summary: summary) }
    }

    func switchToChat(_ chatId: UUID) {
        guard chatId != currentChatId else { return }
        currentChatId = chatId
        errorMessage = nil
        loadMessagesForChat(chatId)
    }

    func deleteChat(_ chatId: UUID) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<GymBroChat>()
        guard let chat = (try? ctx.fetch(descriptor))?.first(where: { $0.id == chatId }) else { return }
        ctx.delete(chat)
        try? ctx.save()
        if currentChatId == chatId {
            currentChatId = nil
            messages = []
            chatTitle = "Новый чат"
        }
    }

    func retry(workouts: [Workout], templates: [WorkoutTemplate] = [], profile: BodyProfile?) {
        guard !isLoading else { return }
        errorMessage = nil
        let summary = lastSummary ?? buildSummary(workouts: workouts, templates: templates, profile: profile)

        if let lastUserMsg = messages.last(where: { $0.role == .user && !$0.isSetComment }) {
            let lastNonComment = messages.last { !$0.isSetComment }
            if lastNonComment?.role == .user {
                Task { await fetchReply(userText: lastUserMsg.text, summary: summary) }
                return
            }
        }

        let hasChatHistory = messages.contains { !$0.isSetComment }
        if !hasChatHistory {
            Task { await fetchOpeningMessage(summary: summary) }
        }
    }

    func send(text: String, workouts: [Workout], templates: [WorkoutTemplate] = [], profile: BodyProfile?, attached: [Workout] = [], attachedTemplates: [WorkoutTemplate] = []) {
        guard !isLoading else { return }
        let isFirstUserMessage = !messages.contains { $0.role == .user && !$0.isSetComment }
        var badges: [String] = []
        if !attached.isEmpty { badges.append("\(attached.count) трен.") }
        if !attachedTemplates.isEmpty { badges.append("\(attachedTemplates.count) шабл.") }
        let attachLabel = badges.isEmpty ? "" : " 📎 [\(badges.joined(separator: ", "))]"
        let userMsg = GymBroMessage(role: .user, text: text + attachLabel)
        messages.append(userMsg)
        persistMessage(userMsg)
        if isFirstUserMessage { autoTitleChat(with: text) }
        let summary = lastSummary ?? buildSummary(workouts: workouts, templates: templates, profile: profile)
        Task { await fetchReply(userText: text, summary: summary, attached: attached, attachedTemplates: attachedTemplates) }
    }

    func markTemplateSaved(messageId: UUID) {
        if let idx = messages.firstIndex(where: { $0.id == messageId }),
           var tmpl = messages[idx].template {
            tmpl.isSaved = true
            messages[idx] = GymBroMessage(id: messageId, role: .ai, text: messages[idx].text, template: tmpl)
        }
    }

    // MARK: - Set comment (AI reaction to completed set)

    func commentOnSet(
        exerciseName: String,
        weight: Double,
        reps: Int,
        setNumber: Int,
        isPR: Bool = false,
        targetWeight: Double? = nil,
        targetReps: Int? = nil,
        previousSets: [(weight: Double, reps: Int)] = []
    ) {
        if let last = lastCommentDate, Date().timeIntervalSince(last) < 15 { return }
        lastCommentDate = Date()

        Task {
            var context = "Упражнение: \(exerciseName), подход #\(setNumber): \(weight) кг × \(reps) повт."

            if let tw = targetWeight, let tr = targetReps, tw > 0 {
                context += "\nПлан из шаблона: \(tw) кг × \(tr) повт."
                let weightRatio = weight / tw
                if weightRatio < 0.6 {
                    context += " (сделал НАМНОГО меньше плана по весу)"
                } else if weightRatio < 0.9 {
                    context += " (вес ниже плана)"
                } else if weightRatio > 1.1 {
                    context += " (превысил план по весу!)"
                }
            }

            if !previousSets.isEmpty {
                let prevStr = previousSets.enumerated().map { "#\($0.offset + 1): \($0.element.weight)кг×\($0.element.reps)" }.joined(separator: ", ")
                context += "\nПредыдущие подходы: \(prevStr)"
                if let lastSet = previousSets.last, reps < lastSet.reps / 2, weight >= lastSet.weight {
                    context += " (резкое падение повторений — возможно вес слишком большой)"
                }
            }

            if isPR { context += "\nЭто НОВЫЙ РЕКОРД!" }

            let prompt = """
            Ты Life Bro — дерзкий мотивирующий лайф-коуч.
            \(context)

            Дай ОДНО короткое предложение (максимум 15 слов). Правила:
            - Если вес сильно ниже плана — подколи, мотивируй поднять.
            - Если повторения резко упали — посоветуй снизить вес и следить за техникой.
            - Если превысил план — похвали.
            - Если по плану — поддержи.
            - Если нет плана — просто мотивируй.
            Один эмодзи. Без markdown. Русский язык.
            """

            do {
                let response = try await commentModel.generateContent(prompt)
                let reply = response.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    guard let reply else { return }
                    let msg = GymBroMessage(role: .ai, text: reply, isSetComment: true)
                    messages.append(msg)
                    persistMessage(msg)
                    hasUnread = true
                    sendSetCommentNotification(comment: reply)
                }
            } catch {
                print("GymBro set comment error: \(error)")
            }
        }
    }

    private func sendSetCommentNotification(comment: String) {
        let content = UNMutableNotificationContent()
        content.title = "Life Bro 💬"
        content.body = comment
        content.sound = .default
        content.userInfo = ["type": "gymBroComment"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "gymBro-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Chat session

    private func createChatSession(summary: WorkoutSummary, fromMessages msgs: [GymBroMessage]) -> Chat {
        let systemPrompt = compactSystemPrompt(summary: summary)
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let chatModel = ai.generativeModel(
            modelName: "gemini-2.5-flash-lite",
            generationConfig: GenerationConfig(temperature: 0.75, maxOutputTokens: 1024),
            systemInstruction: ModelContent(role: "system", parts: systemPrompt)
        )

        let chatMsgs = Array(msgs.filter { !$0.isSetComment }.suffix(50))
        var history: [ModelContent] = []
        var lastRole: String?

        if chatMsgs.first?.role == .ai {
            history.append(ModelContent(role: "user", parts: "Привет"))
            lastRole = "user"
        }

        for msg in chatMsgs {
            let role = msg.role == .user ? "user" : "model"
            if lastRole == role {
                let filler = role == "model"
                    ? ModelContent(role: "user", parts: "Продолжай")
                    : ModelContent(role: "model", parts: "Хорошо.")
                history.append(filler)
            }
            history.append(ModelContent(role: role, parts: msg.text))
            lastRole = role
        }

        return chatModel.startChat(history: history)
    }

    // MARK: - Multi-chat helpers

    private func loadMostRecentChat(workouts: [Workout], templates: [WorkoutTemplate] = [], profile: BodyProfile?) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<GymBroChat>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let chats = (try? ctx.fetch(descriptor)) ?? []

        if let latest = chats.first {
            currentChatId = latest.id
            chatTitle = latest.title
            loadMessagesForChat(latest.id)
        } else {
            createNewChat(workouts: workouts, templates: templates, profile: profile)
        }
    }

    private func loadMessagesForChat(_ chatId: UUID) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<GymBroChat>()
        guard let chat = (try? ctx.fetch(descriptor))?.first(where: { $0.id == chatId }) else { return }
        chatTitle = chat.title
        let sorted = chat.messages.sorted { $0.timestamp < $1.timestamp }
        messages = sorted.map { pm in
            GymBroMessage(
                role: pm.roleRaw == "user" ? .user : .ai,
                text: pm.text,
                isSetComment: pm.isSetComment
            )
        }
    }

    private func migrateOrphanMessages() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<PersistedMessage>(sortBy: [SortDescriptor(\.timestamp)])
        guard let all = try? ctx.fetch(descriptor) else { return }
        let orphans = all.filter { $0.chat == nil }
        guard !orphans.isEmpty else { return }
        let chat = GymBroChat(title: "Чат")
        ctx.insert(chat)
        for msg in orphans { msg.chat = chat }
        if let last = orphans.last { chat.updatedAt = last.timestamp }
        try? ctx.save()
    }

    private func autoTitleChat(with text: String) {
        guard let ctx = modelContext, let chatId = currentChatId else { return }
        let descriptor = FetchDescriptor<GymBroChat>()
        if let chat = (try? ctx.fetch(descriptor))?.first(where: { $0.id == chatId }) {
            let title = String(text.prefix(40)) + (text.count > 40 ? "…" : "")
            chat.title = title
            try? ctx.save()
            chatTitle = title
        }
    }

    // MARK: - Persistence

    private func persistMessage(_ msg: GymBroMessage) {
        guard let ctx = modelContext, let chatId = currentChatId else { return }
        let descriptor = FetchDescriptor<GymBroChat>()
        guard let chat = (try? ctx.fetch(descriptor))?.first(where: { $0.id == chatId }) else { return }
        let pm = PersistedMessage(role: msg.role, text: msg.text, isSetComment: msg.isSetComment)
        pm.chat = chat
        ctx.insert(pm)
        chat.updatedAt = Date()
        try? ctx.save()
    }

    // MARK: - API calls

    private func fetchOpeningMessage(summary: WorkoutSummary) async {
        await MainActor.run { isLoading = true; errorMessage = nil }

        let session = createChatSession(summary: summary, fromMessages: messages)
        let prompt = """
        Пользователь только что открыл чат. Дай короткое приветственное сообщение (2-3 предложения) где:
        1. Поприветствуй и покажи что знаешь статистику (кол-во тренировок, частоту)
        2. Подскажи что можно прикрепить тренировки для детального анализа (кнопка 📎)
        3. Предложи создать шаблон или задать вопрос
        Будь дружелюбным. Эмодзи умеренно. НЕ генерируй шаблон сейчас.
        """

        do {
            let response = try await session.sendMessage(prompt)
            await MainActor.run {
                isLoading = false
                if let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    let (cleanText, template, lifeAction) = parseResponse(text)
                    let aiMsg = GymBroMessage(role: .ai, text: cleanText, template: template, lifeAction: lifeAction)
                    messages.append(aiMsg)
                    persistMessage(aiMsg)
                } else if errorMessage == nil {
                    errorMessage = "Не удалось загрузить — проверь интернет"
                }
            }
        } catch {
            print("GymBro opening error: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription.contains("429")
                    ? "Слишком много запросов. Подожди минуту."
                    : "Ошибка ИИ: \(error.localizedDescription)"
            }
        }
    }

    private func fetchReply(userText: String, summary: WorkoutSummary, attached: [Workout] = [], attachedTemplates: [WorkoutTemplate] = []) async {
        await MainActor.run { isLoading = true; errorMessage = nil }

        let historyMsgs = Array(messages.dropLast())
        let session = createChatSession(summary: summary, fromMessages: historyMsgs)

        var messageText = userText
        if !attached.isEmpty {
            messageText += "\n\nПРИКРЕПЛЁННЫЕ ТРЕНИРОВКИ:\n" + formatWorkouts(attached)
        }
        if !attachedTemplates.isEmpty {
            messageText += "\n\nПРИКРЕПЛЁННЫЕ ШАБЛОНЫ:\n" + formatTemplates(attachedTemplates)
        }
        if !attached.isEmpty || !attachedTemplates.isEmpty {
            messageText += "\nПроанализируй прикреплённые данные в контексте моего вопроса."
        }

        do {
            let response = try await session.sendMessage(messageText)
            await MainActor.run {
                isLoading = false
                if let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    let (cleanText, template, lifeAction) = parseResponse(text)
                    let aiMsg = GymBroMessage(role: .ai, text: cleanText, template: template, lifeAction: lifeAction)
                    messages.append(aiMsg)
                    persistMessage(aiMsg)
                } else if errorMessage == nil {
                    errorMessage = "Не могу ответить, попробуй позже"
                }
            }
        } catch {
            print("GymBro reply error: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription.contains("429")
                    ? "Слишком много запросов. Подожди минуту."
                    : "Ошибка ИИ: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Format workouts for prompt

    private func formatWorkouts(_ workouts: [Workout]) -> String {
        let df = DateFormatter()
        df.dateFormat = "dd.MM"
        return workouts.map { w -> String in
            let dateStr = df.string(from: w.date)
            let dur = w.durationFormatted ?? "?"
            let exLines = w.workoutExercises
                .sorted { $0.order < $1.order }
                .map { we -> String in
                    let sets = we.workoutSets
                        .filter { $0.isCompleted }
                        .sorted { $0.order < $1.order }
                        .map { "\($0.weight)кг×\($0.reps)" }
                        .joined(separator: ", ")
                    return "  · \(we.exercise.name) [\(we.exercise.bodyPart)]: \(sets.isEmpty ? "нет данных" : sets)"
                }
                .joined(separator: "\n")
            return "▸ \(dateStr) «\(w.name)» (\(dur))\n\(exLines)"
        }.joined(separator: "\n")
    }

    private func formatTemplates(_ templates: [WorkoutTemplate]) -> String {
        templates.map { t in
            let exLines = t.exercises
                .sorted { $0.order < $1.order }
                .map { ex in
                    let w = ex.defaultWeight > 0 ? " \(ex.defaultWeight)кг" : ""
                    return "  · \(ex.exerciseName) [\(ex.bodyPart)]: \(ex.defaultSets)×\(ex.defaultReps)\(w)"
                }
                .joined(separator: "\n")
            return "▸ «\(t.name)» (id: \(t.id.uuidString))\n\(exLines)"
        }.joined(separator: "\n")
    }

    // MARK: - Parse response for template JSON

    private func parseResponse(_ raw: String) -> (text: String, template: PendingTemplate?, lifeAction: PendingLifeAction?) {
        if let jsonStart = raw.range(of: "```json"),
           let jsonEnd = raw.range(of: "```", range: jsonStart.upperBound..<raw.endIndex) {
            let jsonStr = String(raw[jsonStart.upperBound..<jsonEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let removeEnd = min(jsonEnd.upperBound, raw.endIndex)
            let cleanText = String(raw[raw.startIndex..<jsonStart.lowerBound] + raw[removeEnd..<raw.endIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if jsonStr.contains("\"life_action\"") {
                return (cleanText, nil, decodeLifeAction(jsonStr))
            }
            return (cleanText, decodeTemplate(jsonStr), nil)
        }

        if let jsonStart2 = raw.range(of: "{\"life_action\"") {
            let substring = raw[jsonStart2.lowerBound...]
            if let endIdx = findMatchingBrace(in: substring) {
                let jsonStr = String(raw[jsonStart2.lowerBound...endIdx])
                let cleanText = raw.replacingOccurrences(of: jsonStr, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (cleanText, nil, decodeLifeAction(jsonStr))
            }
        }

        if let jsonStart2 = raw.range(of: "{\"template\"") {
            let substring = raw[jsonStart2.lowerBound...]
            if let endIdx = findMatchingBrace(in: substring) {
                let jsonStr = String(raw[jsonStart2.lowerBound...endIdx])
                let cleanText = raw.replacingOccurrences(of: jsonStr, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (cleanText, decodeTemplate(jsonStr), nil)
            }
        }

        return (raw, nil, nil)
    }

    private func findMatchingBrace(in str: Substring) -> String.Index? {
        var depth = 0
        var inString = false
        var escape = false
        for idx in str.indices {
            let ch = str[idx]
            if escape { escape = false; continue }
            if ch == "\\" && inString { escape = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            if inString { continue }
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { return idx }
            }
        }
        return nil
    }

    private func decodeTemplate(_ jsonStr: String) -> PendingTemplate? {
        guard let data = jsonStr.data(using: .utf8) else { return nil }

        struct TemplateJSON: Decodable {
            let template: TemplateBody
        }
        struct TemplateBody: Decodable {
            let id: String?
            let name: String
            let exercises: [ExerciseJSON]
        }
        struct ExerciseJSON: Decodable {
            let name: String
            let bodyPart: String
            let sets: Int?
            let reps: Int?
            let weight: Double?
            let timerSeconds: Int?
        }

        do {
            let decoded = try JSONDecoder().decode(TemplateJSON.self, from: data)
            let exercises = decoded.template.exercises.map { ex in
                PendingExercise(
                    name: ex.name,
                    bodyPart: ex.bodyPart,
                    sets: ex.sets ?? 3,
                    reps: ex.reps ?? 10,
                    weight: ex.weight ?? 0,
                    timerSeconds: ex.timerSeconds
                )
            }
            let existingId = decoded.template.id.flatMap { UUID(uuidString: $0) }
            return PendingTemplate(existingId: existingId, name: decoded.template.name, exercises: exercises)
        } catch {
            print("GymBro template parse error: \(error)")
            return nil
        }
    }

    private func decodeLifeAction(_ jsonStr: String) -> PendingLifeAction? {
        guard let data = jsonStr.data(using: .utf8) else { return nil }

        struct LifeActionJSON: Decodable {
            let life_action: LifeActionBody
        }
        struct LifeActionBody: Decodable {
            let habits: [HabitJSON]?
            let todos: [TodoJSON]?
            let goals: [GoalJSON]?
        }
        struct HabitJSON: Decodable {
            let name: String
            let icon: String?
            let colorHex: String?
            let todos: [String]?
        }
        struct TodoJSON: Decodable {
            let title: String
            let priority: Int?
        }
        struct GoalJSON: Decodable {
            let title: String
            let targetCount: Int?
            let period: String?
        }

        do {
            let decoded = try JSONDecoder().decode(LifeActionJSON.self, from: data)
            let habits = (decoded.life_action.habits ?? []).map {
                PendingHabit(name: $0.name, icon: $0.icon ?? "checkmark.circle", colorHex: $0.colorHex ?? "#ff5c3a", todos: $0.todos ?? [])
            }
            let todos = (decoded.life_action.todos ?? []).map {
                PendingTodo(title: $0.title, priority: $0.priority ?? 0)
            }
            let goals = (decoded.life_action.goals ?? []).map {
                PendingGoal(title: $0.title, targetCount: $0.targetCount ?? 1, period: $0.period ?? "week")
            }
            let action = PendingLifeAction(habits: habits, todos: todos, goals: goals)
            return action.isEmpty ? nil : action
        } catch {
            print("LifeBro life_action parse error: \(error)")
            return nil
        }
    }

    func markLifeActionSaved(messageId: UUID) {
        if let idx = messages.firstIndex(where: { $0.id == messageId }),
           var action = messages[idx].lifeAction {
            action.isSaved = true
            messages[idx] = GymBroMessage(id: messageId, role: .ai, text: messages[idx].text, lifeAction: action)
        }
    }

    // MARK: - System prompt

    private func profileBlock(_ summary: WorkoutSummary) -> String {
        var profileStr = "не указан"
        if summary.weight > 0 || summary.height > 0 || summary.age > 0 {
            var parts: [String] = []
            if summary.weight > 0 { parts.append("вес \(String(format: "%.1f", summary.weight)) кг") }
            if summary.height > 0 { parts.append("рост \(String(format: "%.0f", summary.height)) см") }
            if summary.age > 0 { parts.append("возраст \(summary.age) лет") }
            profileStr = parts.joined(separator: ", ")
        }
        return profileStr
    }

    private func statsBlock(_ summary: WorkoutSummary) -> String {
        let muscleStr = summary.musclePercents
            .sorted { $0.value > $1.value }
            .map { "\($0.key): \($0.value)%" }
            .joined(separator: ", ")
        let stagStr = summary.stagnatingExercises.isEmpty ? "нет" : summary.stagnatingExercises.joined(separator: ", ")
        return """
        - Тренировок: \(summary.totalWorkouts), в неделю: \(String(format: "%.1f", summary.avgPerWeek))
        - Мышцы: \(muscleStr)
        - Стагнация: \(stagStr)
        """
    }

    private func templateInstructions(_ summary: WorkoutSummary) -> String {
        var instructions = """
        ШАБЛОНЫ ТРЕНИРОВОК:

        СОЗДАНИЕ нового шаблона — когда пользователь просит составить/создать тренировку, программу или шаблон:
        ```json
        {"template":{"name":"Название","exercises":[{"name":"Упражнение","bodyPart":"Грудь","sets":3,"reps":10,"weight":80,"timerSeconds":90}]}}
        ```

        РЕДАКТИРОВАНИЕ существующего шаблона — когда пользователь просит изменить/отредактировать/обновить прикреплённый или упомянутый шаблон. ОБЯЗАТЕЛЬНО укажи id шаблона:
        ```json
        {"template":{"id":"uuid-шаблона","name":"Новое название","exercises":[{"name":"Упражнение","bodyPart":"Грудь","sets":4,"reps":8,"weight":90,"timerSeconds":120}]}}
        ```

        Правила:
        - Допустимые bodyPart: Грудь, Спина, Ноги, Плечи, Руки, Пресс, Кардио.
        - Подбирай веса и повторения исходя из профиля и истории тренировок.
        - Если данных мало — ставь средние значения.
        - Перед JSON объясни коротко что за программа/какие изменения и почему.
        - При редактировании верни ПОЛНЫЙ список упражнений шаблона (не только изменённые).
        """

        if !summary.knownExercises.isEmpty {
            let grouped = Dictionary(grouping: summary.knownExercises, by: { $0.bodyPart })
            let exerciseList = grouped.sorted { $0.key < $1.key }.map { group in
                let names = group.value.map { $0.name }.joined(separator: ", ")
                return "  \(group.key): \(names)"
            }.joined(separator: "\n")

            instructions += """

            - ВАЖНО: Используй ТОЧНЫЕ названия упражнений из списка ниже, если подходящее упражнение уже есть. Не придумывай новые названия для существующих упражнений. Новые упражнения добавляй только если в списке нет подходящего.

            СУЩЕСТВУЮЩИЕ УПРАЖНЕНИЯ ПОЛЬЗОВАТЕЛЯ:
            \(exerciseList)
            """
        }

        return instructions
    }

    private func lifeActionInstructions() -> String {
        return """
        СОЗДАНИЕ ПРИВЫЧЕК / ЗАДАЧ / ЦЕЛЕЙ:

        Когда пользователь просит создать привычку, задачу или цель — верни JSON:
        ```json
        {"life_action":{"habits":[{"name":"Название","icon":"figure.run","colorHex":"#ff5c3a","todos":["Подзадача 1","Подзадача 2"]}],"todos":[{"title":"Задача","priority":1}],"goals":[{"title":"Цель","targetCount":5,"period":"week"}]}}
        ```

        Правила:
        - Можно создавать одновременно несколько: привычки + задачи + цели.
        - Пустые массивы можно не указывать.
        - У привычки может быть массив todos — конкретные шаги/подзадачи. Когда все подзадачи выполнены, привычка автоматически отмечается как выполненная. Если привычка простая (без шагов) — не указывай todos.
        - Пример: "Создай привычку романтика жене" → привычка с подзадачами: ["Купить цветы", "Написать записку", "Организовать свидание"].
        - icon — название SF Symbol (например: figure.run, drop.fill, book.fill, bed.double.fill, moon.fill, heart.fill, leaf.fill).
        - colorHex: #ff5c3a, #5b8cff, #a855f7, #ffb830, #3aff9e, #ff6b9d.
        - priority для задач: 0 = обычная, 1 = средняя, 2 = высокая.
        - targetCount для целей — количество раз за период.
        - period для целей: "week" (неделя), "month" (месяц), "year" (год). По умолчанию "week".
        - Перед JSON объясни что создаёшь и зачем.
        - Если пользователь спрашивает совет по привычкам — предложи конкретные и верни JSON.
        """
    }

    private func templatesBlock(_ summary: WorkoutSummary) -> String {
        if summary.templates.isEmpty { return "Нет сохранённых шаблонов." }
        return summary.templates.map { t in
            let exStr = t.exercises.joined(separator: ", ")
            return "• «\(t.name)» (id: \(t.id.uuidString)) — \(exStr)"
        }.joined(separator: "\n")
    }

    private func compactSystemPrompt(summary: WorkoutSummary) -> String {
        return """
        Ты Life Bro — дружелюбный лайф-коуч в iOS-приложении LifeOS.
        Ты знаешь про тренировки, финансы, привычки, задачи и цели пользователя.
        Говори как знающий друг: прямо, конкретно, с юмором. Давай советы на стыке данных.
        Например: если пользователь много тратит и мало тренируется — подмечай это.
        Если серия привычек рвётся — мотивируй. Отвечай на том же языке что и пользователь.
        У тебя есть долгосрочная память — ты помнишь все прошлые разговоры с пользователем.

        ПРОФИЛЬ: \(profileBlock(summary))

        ТРЕНИРОВКИ (90 дней):
        \(statsBlock(summary))

        ПРИВЫЧКИ:
        \(habitsBlock(summary))

        ЗАДАЧИ:
        \(todosBlock(summary))

        ЦЕЛИ НЕДЕЛИ:
        \(goalsBlock(summary))

        ФИНАНСЫ:
        \(financeBlock(summary))

        ШАБЛОНЫ:
        \(templatesBlock(summary))

        \(templateInstructions(summary))

        \(lifeActionInstructions())
        """
    }

    private func habitsBlock(_ summary: WorkoutSummary) -> String {
        guard !summary.habits.isEmpty else { return "Привычки не заведены." }
        return summary.habits.map { h in
            let status = h.completedToday ? "✅" : "❌"
            return "\(status) \(h.name) — серия \(h.streak) дн."
        }.joined(separator: "\n")
    }

    private func todosBlock(_ summary: WorkoutSummary) -> String {
        return "Невыполненных задач: \(summary.pendingTodos). Выполнено сегодня: \(summary.completedTodosToday)."
    }

    private func goalsBlock(_ summary: WorkoutSummary) -> String {
        guard !summary.weeklyGoals.isEmpty else { return "Целей на неделю нет." }
        return summary.weeklyGoals.map { g in
            "• \(g.title): \(g.current)/\(g.target)"
        }.joined(separator: "\n")
    }

    private func financeBlock(_ summary: WorkoutSummary) -> String {
        return """
        Баланс: \(summary.financeBalance) ₸
        Сегодня: расход \(summary.todayExpense), доход \(summary.todayIncome)
        За месяц расходы: \(summary.monthExpense)
        """
    }

    // MARK: - Build summary

    private func buildSummary(workouts: [Workout], templates: [WorkoutTemplate] = [], profile: BodyProfile?) -> WorkoutSummary {
        let cal = Calendar.current
        let since = cal.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let recent = workouts.filter { $0.finishedAt != nil && $0.date >= since }

        var volumeByMuscle: [String: Double] = [:]
        var setsByMuscle: [String: Int] = [:]
        var exerciseLastWeight: [String: [(date: Date, weight: Double)]] = [:]

        for w in recent {
            for we in w.workoutExercises {
                let muscle = we.exercise.bodyPart
                let completedSets = we.workoutSets.filter { $0.isCompleted }
                let vol = completedSets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
                volumeByMuscle[muscle, default: 0] += vol
                setsByMuscle[muscle, default: 0] += completedSets.count
                if let maxW = completedSets.map(\.weight).max(), maxW > 0 {
                    exerciseLastWeight[we.exercise.name, default: []].append((date: w.date, weight: maxW))
                }
            }
        }

        let totalSets = setsByMuscle.values.reduce(0, +)
        var musclePercents: [String: Int] = [:]
        for (m, s) in setsByMuscle {
            musclePercents[m] = totalSets > 0 ? Int(Double(s) / Double(totalSets) * 100) : 0
        }

        let threeWeeksAgo = cal.date(byAdding: .day, value: -21, to: Date()) ?? Date()
        var stagnating: [String] = []
        for (name, entries) in exerciseLastWeight {
            let recent3w = entries.filter { $0.date >= threeWeeksAgo }
            if recent3w.count >= 3 {
                let weights = recent3w.map { $0.weight }
                if weights.max() == weights.min() { stagnating.append(name) }
            }
        }

        let weeks = max(1.0, Double(cal.dateComponents([.weekOfYear], from: recent.first?.date ?? Date(), to: Date()).weekOfYear ?? 1))

        var summary = WorkoutSummary(
            totalWorkouts: recent.count,
            avgPerWeek: Double(recent.count) / weeks,
            musclePercents: musclePercents,
            stagnatingExercises: stagnating,
            volumeByMuscle: volumeByMuscle
        )
        if let profile {
            summary.weight = profile.weight
            summary.height = profile.height
            summary.age = profile.age
        }
        summary.templates = templates.map { t in
            (id: t.id, name: t.name, exercises: t.exercises.sorted { $0.order < $1.order }.map { $0.exerciseName })
        }

        var seenExercises = Set<String>()
        var knownExercises: [(name: String, bodyPart: String)] = []
        for w in workouts {
            for we in w.workoutExercises {
                let key = we.exercise.name + "|" + we.exercise.bodyPart
                if seenExercises.insert(key).inserted {
                    knownExercises.append((name: we.exercise.name, bodyPart: we.exercise.bodyPart))
                }
            }
        }
        for t in templates {
            for te in t.exercises {
                let key = te.exerciseName + "|" + te.bodyPart
                if seenExercises.insert(key).inserted {
                    knownExercises.append((name: te.exerciseName, bodyPart: te.bodyPart))
                }
            }
        }
        summary.knownExercises = knownExercises.sorted { $0.bodyPart < $1.bodyPart }

        // Life data from modelContext
        if let ctx = modelContext {
            let today = Date()

            if let habits = try? ctx.fetch(FetchDescriptor<Habit>(predicate: #Predicate { !$0.archived })) {
                summary.habits = habits.map { h in
                    (name: h.name, streak: h.streak(), completedToday: h.isCompleted(on: today))
                }
            }

            if let todos = try? ctx.fetch(FetchDescriptor<TodoItem>()) {
                summary.pendingTodos = todos.filter { !$0.completed }.count
                summary.completedTodosToday = todos.filter { $0.completed && cal.isDateInToday($0.createdAt) }.count
            }

            if let goals = try? ctx.fetch(FetchDescriptor<WeeklyGoal>()) {
                summary.weeklyGoals = goals.filter { $0.isCurrentWeek }.map {
                    (title: $0.title, current: $0.currentCount, target: $0.targetCount)
                }
            }

            if let accounts = try? ctx.fetch(FetchDescriptor<FinanceAccount>()),
               let transactions = try? ctx.fetch(FetchDescriptor<FinanceTransaction>()) {
                let monthAgo = cal.date(byAdding: .month, value: -1, to: today) ?? today
                summary.financeBalance = accounts.reduce(0) { total, acc in
                    let txs = transactions.filter { $0.accountID == acc.id }
                    let inc = txs.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
                    let exp = txs.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
                    return total + acc.balance + inc - exp
                }
                let todayTx = transactions.filter { cal.isDateInToday($0.date) }
                summary.todayExpense = todayTx.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
                summary.todayIncome = todayTx.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
                summary.monthExpense = transactions.filter { $0.date >= monthAgo && $0.type == .expense }.reduce(0) { $0 + $1.amount }
            }
        }

        return summary
    }

    // MARK: - Build insights

    private func buildInsights(summary: WorkoutSummary) -> [GymBroInsight] {
        var chips: [GymBroInsight] = []
        for (muscle, pct) in summary.musclePercents.sorted(by: { $0.value > $1.value }) where pct <= 5 {
            chips.append(GymBroInsight(icon: "⚖️", label: "Дисбаланс", value: "\(muscle) \(pct)%", severity: .alert))
        }
        for ex in summary.stagnatingExercises.prefix(2) {
            chips.append(GymBroInsight(icon: "📉", label: "Стагнация", value: ex, severity: .warn))
        }
        if summary.totalWorkouts > 10 {
            chips.append(GymBroInsight(icon: "📈", label: "Активность", value: "\(summary.totalWorkouts) трен.", severity: .good))
        }

        let brokenStreaks = summary.habits.filter { !$0.completedToday && $0.streak == 0 }
        if !brokenStreaks.isEmpty {
            chips.append(GymBroInsight(icon: "🔗", label: "Привычки", value: "\(brokenStreaks.count) не выполн.", severity: .warn))
        }
        let maxStreak = summary.habits.map { $0.streak }.max() ?? 0
        if maxStreak >= 7 {
            chips.append(GymBroInsight(icon: "🔥", label: "Серия", value: "\(maxStreak) дн.", severity: .good))
        }
        if summary.pendingTodos > 5 {
            chips.append(GymBroInsight(icon: "📋", label: "Задачи", value: "\(summary.pendingTodos) ожидают", severity: .warn))
        }
        if summary.financeBalance < 0 {
            chips.append(GymBroInsight(icon: "💸", label: "Баланс", value: "отрицательный", severity: .alert))
        }

        if chips.isEmpty {
            chips.append(GymBroInsight(icon: "🔥", label: "Анализ", value: "готов к работе", severity: .good))
        }
        return chips
    }
}

private struct WorkoutSummary {
    let totalWorkouts: Int
    let avgPerWeek: Double
    let musclePercents: [String: Int]
    let stagnatingExercises: [String]
    let volumeByMuscle: [String: Double]
    var weight: Double = 0
    var height: Double = 0
    var age: Int = 0
    var templates: [(id: UUID, name: String, exercises: [String])] = []
    var knownExercises: [(name: String, bodyPart: String)] = []

    // Life data
    var habits: [(name: String, streak: Int, completedToday: Bool)] = []
    var pendingTodos: Int = 0
    var completedTodosToday: Int = 0
    var weeklyGoals: [(title: String, current: Int, target: Int)] = []
    var financeBalance: Int = 0
    var todayExpense: Int = 0
    var todayIncome: Int = 0
    var monthExpense: Int = 0
}
