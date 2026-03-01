import SwiftData
import Foundation
import FirebaseAI

// MARK: - Generated Quest Model

@Model
final class GeneratedQuest {
    var id: UUID = UUID()
    var weekId: String = ""
    var title: String = ""
    var subtitle: String = ""
    var icon: String = ""
    var colorHex: String = "#ff5c3a"
    var xp: Int = 100
    var targetType: String = ""
    var targetValue: Double = 0
    var order: Int = 0
    var isCompleted: Bool = false

    init(weekId: String, title: String, subtitle: String, icon: String, colorHex: String, xp: Int, targetType: String, targetValue: Double, order: Int) {
        self.id = UUID()
        self.weekId = weekId
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.colorHex = colorHex
        self.xp = xp
        self.targetType = targetType
        self.targetValue = targetValue
        self.order = order
        self.isCompleted = false
    }
}

private struct QuestListJSON: Decodable { let quests: [QuestItemJSON] }
private struct QuestItemJSON: Decodable {
    let title: String
    let subtitle: String
    let icon: String
    let colorHex: String
    let xp: Int
    let targetType: String
    let targetValue: Double
}

// MARK: - Gamification Models

struct WeeklyStreak {
    let current: Int
    let record: Int
    let completedThisWeek: Int
    let goalPerWeek: Int
    let weekHistory: [Bool]   // last 6 weeks (true = completed)
    let daysLeftInWeek: Int

    var progressText: String {
        let remaining = max(0, goalPerWeek - completedThisWeek)
        if remaining == 0 { return "Неделя закрыта! 🎉" }
        return "Ещё \(remaining) тр. до цели"
    }
}

struct MuscleGroupStatus: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let daysAgo: Int?     // nil = никогда
    let windowDays: Int   // = 10

    var state: MuscleState {
        guard let d = daysAgo else { return .never }
        if d <= windowDays - 3 { return .done }
        if d <= windowDays     { return .warning }
        return .missed
    }

    var label: String {
        guard let d = daysAgo else { return "✗ никогда" }
        if d == 0 { return "✓ сегодня" }
        if state == .done    { return "✓ \(d) дн. назад" }
        if state == .warning { return "⚠ \(d) дн. назад" }
        return "✗ \(d) дн. назад"
    }

    var color: String {
        switch state {
        case .done:    return "green"
        case .warning: return "yellow"
        case .missed:  return "red"
        case .never:   return "red"
        }
    }

    enum MuscleState { case done, warning, missed, never }
}

struct PRGoal: Identifiable {
    let id = UUID()
    let exerciseName: String
    let emoji: String
    let currentKg: Double
    let goalKg: Double

    var progress: Double { min(1.0, currentKg / goalKg) }
    var remaining: Double { max(0, goalKg - currentKg) }
    var isAchieved: Bool { currentKg >= goalKg }
}

// MARK: - Gamification Manager

struct GamificationManager {
    static let windowDays = 10
    static let weeklyGoal = 3

    static func weeklyStreak(workouts: [Workout]) -> WeeklyStreak {
        let cal = Calendar.current
        let finished = workouts.filter { $0.finishedAt != nil }

        // completed this week
        let startOfWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let thisWeekCount = finished.filter { $0.date >= startOfWeek }.count

        // week history (last 7 weeks)
        var history: [Bool] = []
        for weekOffset in stride(from: -6, through: -1, by: 1) {
            guard let ws = cal.date(byAdding: .weekOfYear, value: weekOffset, to: startOfWeek),
                  let we = cal.date(byAdding: .weekOfYear, value: weekOffset + 1, to: startOfWeek) else { continue }
            let count = finished.filter { $0.date >= ws && $0.date < we }.count
            history.append(count >= weeklyGoal)
        }

        // current streak (count consecutive completed weeks going back)
        var streak = 0
        for completed in history.reversed() {
            if completed { streak += 1 } else { break }
        }

        // record streak
        var maxStreak = 0
        var cur = 0
        for completed in history {
            cur = completed ? cur + 1 : 0
            maxStreak = max(maxStreak, cur)
        }
        maxStreak = max(maxStreak, streak)

        // days left in week
        let weekday = cal.component(.weekday, from: Date())
        let daysLeft = max(0, 8 - weekday) // 1=Sun→7, Mon=2→6 days left

        return WeeklyStreak(
            current: streak,
            record: max(maxStreak, streak),
            completedThisWeek: thisWeekCount,
            goalPerWeek: weeklyGoal,
            weekHistory: history,
            daysLeftInWeek: daysLeft
        )
    }

    static func muscleStatuses(workouts: [Workout]) -> [MuscleGroupStatus] {
        let cal = Calendar.current
        let now = Date()
        let finished = workouts.filter { $0.finishedAt != nil }

        let groups: [(String, String, String)] = [
            ("Ноги", "🦵", "Ноги"),
            ("Грудь", "🫁", "Грудь"),
            ("Спина", "🔙", "Спина"),
            ("Руки", "💪", "Руки"),
            ("Плечи", "🙆", "Плечи"),
            ("Пресс", "🔥", "Пресс"),
        ]

        return groups.map { (name, emoji, bodyPart) in
            // find the most recent workout that included this body part
            let lastDate = finished
                .filter { w in
                    w.workoutExercises.contains { we in
                        we.exercise.bodyPart.lowercased() == bodyPart.lowercased() &&
                        we.workoutSets.contains { $0.isCompleted }
                    }
                }
                .map { $0.date }
                .max()

            let daysAgo = lastDate.map { cal.dateComponents([.day], from: $0, to: now).day ?? 0 }

            return MuscleGroupStatus(name: name, emoji: emoji, daysAgo: daysAgo, windowDays: windowDays)
        }
    }

    static func xpTotal(workouts: [Workout], quests: [GeneratedQuest] = []) -> Int {
        let finished = workouts.filter { $0.finishedAt != nil }
        let workoutXP = finished.count * 50
        let questXP = quests.filter { $0.isCompleted }.reduce(0) { $0 + $1.xp }
        return workoutXP + questXP
    }

    // MARK: - Weekly Quest ID

    static func currentWeekId() -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return "\(comps.yearForWeekOfYear ?? 2026)-W\(String(format: "%02d", comps.weekOfYear ?? 1))"
    }

    static func thisWeekStart() -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
    }

    // MARK: - Quest Progress Computation

    static func questProgress(targetType: String, targetValue: Double, workouts: [Workout]) -> (current: Double, label: String) {
        let weekStart = thisWeekStart()
        let weekWorks = workouts.filter { $0.finishedAt != nil && $0.date >= weekStart }
        let allSets = weekWorks.flatMap { $0.workoutExercises }.flatMap { $0.workoutSets }.filter { $0.isCompleted }

        switch targetType {
        case "workouts":
            let c = Double(weekWorks.count)
            return (c, "\(Int(c)) из \(Int(targetValue)) тренировок")

        case "total_sets":
            let c = Double(allSets.count)
            return (c, "\(Int(c)) из \(Int(targetValue)) подходов")

        case "total_volume":
            let vol = allSets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
            let fmt = { (v: Double) -> String in v >= 1000 ? String(format: "%.1f т", v / 1000) : String(format: "%.0f кг", v) }
            return (vol, "\(fmt(vol)) из \(fmt(targetValue))")

        case "unique_muscles":
            let muscles = Set(weekWorks.flatMap { $0.workoutExercises }
                .filter { we in we.workoutSets.contains { $0.isCompleted } }
                .map { $0.exercise.bodyPart })
            let c = Double(muscles.count)
            return (c, "\(Int(c)) из \(Int(targetValue)) групп")

        case "unique_exercises":
            let exs = Set(weekWorks.flatMap { $0.workoutExercises }
                .filter { we in we.workoutSets.contains { $0.isCompleted } }
                .map { $0.exercise.name })
            let c = Double(exs.count)
            return (c, "\(Int(c)) из \(Int(targetValue)) упражнений")

        default:
            if targetType.hasPrefix("bodypart:") {
                let part = String(targetType.dropFirst("bodypart:".count))
                let sets = weekWorks.flatMap { $0.workoutExercises }
                    .filter { $0.exercise.bodyPart == part }
                    .flatMap { $0.workoutSets }
                    .filter { $0.isCompleted }
                let c = Double(sets.count)
                return (c, "\(Int(c)) из \(Int(targetValue)) сетов (\(part))")
            }
            return (0, "0 из \(Int(targetValue))")
        }
    }

    // MARK: - AI Quest Generation

    static func generateQuests(workouts: [Workout], profile: BodyProfile?, context: ModelContext) async {
        let weekId = currentWeekId()

        let predicate = #Predicate<GeneratedQuest> { $0.weekId == weekId }
        let descriptor = FetchDescriptor(predicate: predicate)
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return }

        let finished = workouts.filter { $0.finishedAt != nil }
        let cal = Calendar.current
        let since = cal.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recent = finished.filter { $0.date >= since }

        let weeks = Double(cal.dateComponents([.weekOfYear], from: recent.first?.date ?? Date(), to: Date()).weekOfYear ?? 1)
        let avgPerWeek: Double = recent.isEmpty ? 0 : Double(recent.count) / max(1, weeks)

        let allCompletedSets = recent.flatMap { $0.workoutExercises }.flatMap { $0.workoutSets }.filter { $0.isCompleted }
        let avgSetsPerWorkout: Int = recent.isEmpty ? 0 : allCompletedSets.count / max(1, recent.count)

        var totalVolume: Double = 0
        for s in allCompletedSets { totalVolume += s.weight * Double(s.reps) }
        let avgVolume: Double = recent.isEmpty ? 0 : totalVolume / Double(max(1, recent.count))

        var muscleFreq: [String: Int] = [:]
        for w in recent {
            for we in w.workoutExercises where we.workoutSets.contains(where: { $0.isCompleted }) {
                muscleFreq[we.exercise.bodyPart, default: 0] += 1
            }
        }
        let weakMuscle = muscleFreq.min(by: { $0.value < $1.value })?.key ?? "Ноги"
        let strongMuscle = muscleFreq.max(by: { $0.value < $1.value })?.key ?? "Грудь"

        var profileStr = "не указан"
        if let p = profile {
            var parts: [String] = []
            if p.weight > 0 { parts.append("вес \(String(format: "%.0f", p.weight))кг") }
            if p.age > 0 { parts.append("возраст \(p.age)") }
            if !parts.isEmpty { profileStr = parts.joined(separator: ", ") }
        }

        let prompt = """
        Ты фитнес-тренер. Сгенерируй 5 недельных квестов для пользователя.

        Профиль: \(profileStr)
        Тренировок в неделю: \(String(format: "%.1f", avgPerWeek))
        Средний объём за тренировку: \(String(format: "%.0f", avgVolume)) кг
        Среднее подходов за тренировку: \(avgSetsPerWorkout)
        Слабая группа: \(weakMuscle)
        Сильная группа: \(strongMuscle)

        Допустимые targetType:
        - "workouts" — количество тренировок
        - "total_sets" — общее количество подходов
        - "total_volume" — суммарный объём в кг (вес × повторения)
        - "unique_muscles" — количество уникальных групп мышц (макс 7: Грудь, Спина, Ноги, Плечи, Руки, Пресс, Кардио)
        - "unique_exercises" — количество уникальных упражнений
        - "bodypart:ГРУППА" — подходы на конкретную группу (например "bodypart:Ноги")

        Допустимые цвета: #ff5c3a, #5b8cff, #a855f7, #ffb830, #3aff9e

        Правила:
        - Квесты должны быть реалистичными на основе текущей активности пользователя.
        - Один квест на слабую группу мышц.
        - targetValue — число (целое для подходов/тренировок, с плавающей точкой для объёма).
        - XP от 50 до 200 в зависимости от сложности.
        - Иконки — один эмодзи.
        - Ответ ТОЛЬКО JSON, без текста.

        Формат:
        ```json
        {"quests":[{"title":"...","subtitle":"...","icon":"💪","colorHex":"#ff5c3a","xp":100,"targetType":"workouts","targetValue":3}]}
        ```
        """

        do {
            let ai = FirebaseAI.firebaseAI(backend: .googleAI())
            let model = ai.generativeModel(
                modelName: "gemini-2.5-flash-lite",
                generationConfig: GenerationConfig(temperature: 0.8, maxOutputTokens: 1024)
            )
            let response = try await model.generateContent(prompt)
            guard let text = response.text else { return }

            guard let jsonStr = extractJSON(from: text),
                  let data = jsonStr.data(using: String.Encoding.utf8) else { return }

            let decoded = try JSONDecoder().decode(QuestListJSON.self, from: data)

            await MainActor.run {
                for (i, q) in decoded.quests.prefix(5).enumerated() {
                    let quest = GeneratedQuest(
                        weekId: weekId,
                        title: q.title,
                        subtitle: q.subtitle,
                        icon: q.icon,
                        colorHex: q.colorHex,
                        xp: q.xp,
                        targetType: q.targetType,
                        targetValue: q.targetValue,
                        order: i
                    )
                    context.insert(quest)
                }
                try? context.save()
            }
        } catch {
            print("Quest generation error: \(error)")
            await MainActor.run {
                saveFallbackQuests(weekId: weekId, avgPerWeek: avgPerWeek, avgSetsPerWorkout: avgSetsPerWorkout, avgVolume: avgVolume, weakMuscle: weakMuscle, context: context)
            }
        }
    }

    private static func extractJSON(from text: String) -> String? {
        if let start = text.range(of: "```json"), let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.range(of: "{\"quests\"") {
            var depth = 0; var inStr = false; var esc = false
            for idx in text[start.lowerBound...].indices {
                let ch = text[idx]
                if esc { esc = false; continue }
                if ch == "\\" && inStr { esc = true; continue }
                if ch == "\"" { inStr.toggle(); continue }
                if inStr { continue }
                if ch == "{" { depth += 1 }
                else if ch == "}" { depth -= 1; if depth == 0 { return String(text[start.lowerBound...idx]) } }
            }
        }
        return nil
    }

    private static func saveFallbackQuests(weekId: String, avgPerWeek: Double, avgSetsPerWorkout: Int, avgVolume: Double, weakMuscle: String, context: ModelContext) {
        let workoutsGoal = max(2, Int(avgPerWeek.rounded()) + 1)
        let setsGoal = max(30, (avgSetsPerWorkout * workoutsGoal) + 10)
        let volGoal = max(3000, (avgVolume * Double(workoutsGoal)) * 1.1)

        let fallback: [(String, String, String, String, Int, String, Double)] = [
            ("📅", "Закрой неделю", "Проведи \(workoutsGoal) тренировки", "#5b8cff", 80, "workouts", Double(workoutsGoal)),
            ("🔁", "Набери \(setsGoal) подходов", "Выполни \(setsGoal) подходов за неделю", "#a855f7", 100, "total_sets", Double(setsGoal)),
            ("🏋️", "Объём \(String(format: "%.0f", volGoal)) кг", "Суммарный тоннаж за неделю", "#ffb830", 150, "total_volume", volGoal),
            ("💪", "Прокачай \(weakMuscle.lowercased())", "Минимум 8 подходов на \(weakMuscle.lowercased())", "#ff5c3a", 120, "bodypart:\(weakMuscle)", 8),
            ("🎯", "Разнообразие", "Выполни 6 разных упражнений", "#3aff9e", 90, "unique_exercises", 6),
        ]
        for (i, q) in fallback.enumerated() {
            context.insert(GeneratedQuest(weekId: weekId, title: q.1, subtitle: q.2, icon: q.0, colorHex: q.3, xp: q.4, targetType: q.5, targetValue: q.6, order: i))
        }
        try? context.save()
    }

    // MARK: - XP & Levels

    static let levels: [(Int, String, String)] = [
        (0,    "Новичок",   "🌱"),
        (300,  "Любитель",  "💧"),
        (700,  "Спортсмен", "⚡"),
        (1400, "Атлет",     "🔥"),
        (2500, "Элита",     "💎"),
        (4000, "Легенда",   "👑"),
    ]

    static func level(xp: Int) -> (name: String, emoji: String, level: Int, progressInLevel: Double, xpForNext: Int, xpAtStart: Int) {
        var current = levels[0]
        var next = levels[1]
        var levelNum = 1

        for i in 0..<levels.count {
            if xp >= levels[i].0 {
                current = levels[i]
                levelNum = i + 1
                next = i + 1 < levels.count ? levels[i + 1] : levels[i]
            }
        }

        let range = Double(next.0 - current.0)
        let progress = range > 0 ? Double(xp - current.0) / range : 1.0
        return (current.1, current.2, levelNum, min(1, progress), next.0, current.0)
    }
}
