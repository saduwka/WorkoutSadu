import Foundation
import SwiftData
import FirebaseAuth
import FirebaseStorage

// MARK: - Backup payload (Codable DTOs)

struct BackupPayload: Codable {
    let version: Int
    let exportedAt: String
    let exercises: [BackupExercise]
    let workouts: [BackupWorkout]
    let templates: [BackupTemplate]
    let financeAccounts: [BackupFinanceAccount]
    let financeTransactions: [BackupFinanceTransaction]
    let habits: [BackupHabit]
    let habitEntries: [BackupHabitEntry]
    let todos: [BackupTodo]
    let weeklyGoals: [BackupWeeklyGoal]
    let bodyProfiles: [BackupBodyProfile]
    let mealEntries: [BackupMealEntry]
}

struct BackupExercise: Codable {
    let id: String
    let name: String
    let bodyPart: String
    let gifURL: String?
}

struct BackupWorkoutSet: Codable {
    let id: String
    let order: Int
    let reps: Int
    let weight: Double
    let isCompleted: Bool
    let completedAt: Date?
}

struct BackupWorkoutExercise: Codable {
    let id: String
    let order: Int
    let exerciseId: String
    let timerSeconds: Int?
    let sets: [BackupWorkoutSet]
}

struct BackupWorkout: Codable {
    let id: String
    let name: String
    let date: Date
    let startedAt: Date?
    let finishedAt: Date?
    let exercises: [BackupWorkoutExercise]
}

struct BackupTemplateExercise: Codable {
    let id: String
    let order: Int
    let exerciseName: String
    let bodyPart: String
    let defaultSets: Int
    let defaultReps: Int
    let defaultWeight: Double
    let timerSeconds: Int?
}

struct BackupTemplate: Codable {
    let id: String
    let name: String
    let createdAt: Date
    let exercises: [BackupTemplateExercise]
}

struct BackupFinanceAccount: Codable {
    let id: String
    let name: String
    let balance: Int
    let icon: String
    let colorHex: String
    let createdAt: Date
}

struct BackupFinanceTransaction: Codable {
    let id: String
    let name: String
    let amount: Int
    let categoryRaw: String
    let typeRaw: String
    let date: Date
    let accountID: String?
}

struct BackupHabit: Codable {
    let id: String
    let name: String
    let icon: String
    let colorHex: String
    let createdAt: Date
    let archived: Bool
}

struct BackupHabitEntry: Codable {
    let id: String
    let date: Date
    let habitId: String
}

struct BackupTodo: Codable {
    let id: String
    let title: String
    let completed: Bool
    let dueDate: Date?
    let createdAt: Date
    let priority: Int
    let habitId: String?
}

struct BackupWeeklyGoal: Codable {
    let id: String
    let title: String
    let targetCount: Int
    let currentCount: Int
    let weekStart: Date
    let periodRaw: String
    let createdAt: Date
}

struct BackupBodyProfile: Codable {
    let weight: Double
    let height: Double
    let age: Int
    let birthDate: Date?
    let restingHeartRate: Int
    let bodyFatPercent: Double?
    let goalRaw: String
    let targetWeightKg: Double
    let updatedAt: Date
}

struct BackupMealEntry: Codable {
    let id: String
    let name: String
    let calories: Int
    let protein: Double
    let fat: Double
    let carbs: Double
    let grams: Double
    let date: Date
    let mealTypeRaw: String
}

// MARK: - Service

/// Автоэкспорт данных SwiftData в Firebase Storage раз в 24 часа (при открытии приложения).
/// Требуется: добавить в Xcode FirebaseAuth и FirebaseStorage из firebase-ios-sdk.
/// В Firebase Console: включить Anonymous Sign-In (Authentication) и настроить Storage rules для чтения/записи по пути backups/{userId}/.
final class FirebaseBackupService {
    static let shared = FirebaseBackupService()

    private let lastExportKey = "FirebaseBackup.lastExportDate"
    private let exportInterval: TimeInterval = 24 * 60 * 60 // 24 часа
    private let storagePath = "backups"

    private init() {}

    /// Вызвать при запуске/возврате в приложение. Если прошло ≥24 ч — выполняет экспорт в фоне.
    @MainActor
    func tryExportIfNeeded(context: ModelContext) async {
        guard shouldExport() else { return }
        do {
            try await signInAnonymouslyIfNeeded()
            let data = try buildBackupPayload(context: context)
            try await upload(data: data)
            saveLastExportDate()
        } catch {
            print("[FirebaseBackup] Export failed: \(error.localizedDescription)")
        }
    }

    /// Принудительный экспорт.
    @MainActor
    func forceExport(context: ModelContext) async throws {
        try await signInAnonymouslyIfNeeded()
        let data = try buildBackupPayload(context: context)
        try await upload(data: data)
        saveLastExportDate()
    }

    /// Восстановление из Firebase. ВНИМАНИЕ: Очищает текущие данные!
    @MainActor
    func restoreFromBackup(context: ModelContext) async throws {
        try await signInAnonymouslyIfNeeded()
        let data = try await download()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)

        // 1. Clear current data
        let models: [any PersistentModel.Type] = [
            Exercise.self, Workout.self, WorkoutExercise.self, WorkoutSet.self,
            WorkoutTemplate.self, FinanceAccount.self, FinanceTransaction.self,
            Habit.self, HabitEntry.self, TodoItem.self, WeeklyGoal.self,
            BodyProfile.self, MealEntry.self, WeightEntry.self
        ]
        for model in models {
            try context.delete(model: model)
        }
        try context.save()

        // 2. Restore Exercises
        var exerciseMap: [String: Exercise] = [:]
        for be in payload.exercises {
            let ex = Exercise(name: be.name, bodyPart: be.bodyPart, gifURL: be.gifURL)
            if let uid = UUID(uuidString: be.id) { ex.id = uid }
            context.insert(ex)
            exerciseMap[be.id] = ex
        }

        // 3. Restore Workouts
        for bw in payload.workouts {
            let w = Workout(name: bw.name, date: bw.date)
            if let uid = UUID(uuidString: bw.id) { w.id = uid }
            w.startedAt = bw.startedAt
            w.finishedAt = bw.finishedAt
            context.insert(w)
            
            for bwe in bw.exercises {
                guard let ex = exerciseMap[bwe.exerciseId] else { continue }
                let we = WorkoutExercise(exercise: ex, timerSeconds: bwe.timerSeconds, order: bwe.order)
                if let uid = UUID(uuidString: bwe.id) { we.id = uid }
                we.workout = w
                context.insert(we)
                
                for bs in bwe.sets {
                    let s = WorkoutSet(order: bs.order, reps: bs.reps, weight: bs.weight)
                    if let uid = UUID(uuidString: bs.id) { s.id = uid }
                    s.isCompleted = bs.isCompleted
                    s.completedAt = bs.completedAt
                    we.workoutSets.append(s)
                    context.insert(s)
                }
            }
        }

        // 4. Restore Templates
        for bt in payload.templates {
            let t = WorkoutTemplate(name: bt.name)
            if let uid = UUID(uuidString: bt.id) { t.id = uid }
            t.createdAt = bt.createdAt
            context.insert(t)
            
            for bte in bt.exercises {
                let te = TemplateExercise(
                    order: bte.order,
                    exerciseName: bte.exerciseName,
                    bodyPart: bte.bodyPart,
                    timerSeconds: bte.timerSeconds,
                    defaultSets: bte.defaultSets,
                    defaultReps: bte.defaultReps,
                    defaultWeight: bte.defaultWeight
                )
                if let uid = UUID(uuidString: bte.id) { te.id = uid }
                t.exercises.append(te)
                context.insert(te)
            }
        }

        // 5. Restore Finance
        var accountMap: [String: FinanceAccount] = [:]
        for ba in payload.financeAccounts {
            let a = FinanceAccount(name: ba.name, balance: ba.balance, icon: ba.icon, colorHex: ba.colorHex)
            if let uid = UUID(uuidString: ba.id) { a.id = uid }
            a.createdAt = ba.createdAt
            context.insert(a)
            accountMap[ba.id] = a
        }
        for bt in payload.financeTransactions {
            let category = FinanceCategory(rawValue: bt.categoryRaw) ?? .other
            let type = FinanceType(rawValue: bt.typeRaw) ?? .expense
            let t = FinanceTransaction(name: bt.name, amount: bt.amount, category: category, type: type, date: bt.date, accountID: bt.accountID != nil ? UUID(uuidString: bt.accountID!) : nil)
            if let uid = UUID(uuidString: bt.id) { t.id = uid }
            context.insert(t)
        }

        // 6. Restore Habits
        var habitMap: [String: Habit] = [:]
        for bh in payload.habits {
            let h = Habit(name: bh.name, icon: bh.icon, colorHex: bh.colorHex)
            if let uid = UUID(uuidString: bh.id) { h.id = uid }
            h.createdAt = bh.createdAt
            h.archived = bh.archived
            context.insert(h)
            habitMap[bh.id] = h
        }
        for bhe in payload.habitEntries {
            guard let h = habitMap[bhe.habitId] else { continue }
            let e = HabitEntry(date: bhe.date, habit: h)
            if let uid = UUID(uuidString: bhe.id) { e.id = uid }
            context.insert(e)
        }

        // 7. Restore Todos
        for bt in payload.todos {
            let habit = bt.habitId != nil ? habitMap[bt.habitId!] : nil
            let t = TodoItem(title: bt.title, dueDate: bt.dueDate, priority: bt.priority)
            if let uid = UUID(uuidString: bt.id) { t.id = uid }
            t.completed = bt.completed
            t.createdAt = bt.createdAt
            t.habit = habit
            context.insert(t)
        }

        // 8. Restore Goals
        for bg in payload.weeklyGoals {
            let period = GoalPeriod(rawValue: bg.periodRaw) ?? .week
            let g = WeeklyGoal(title: bg.title, targetCount: bg.targetCount, period: period)
            if let uid = UUID(uuidString: bg.id) { g.id = uid }
            g.currentCount = bg.currentCount
            g.weekStart = bg.weekStart
            g.createdAt = bg.createdAt
            context.insert(g)
        }

        // 9. Restore Profiles
        for bp in payload.bodyProfiles {
            let p = BodyProfile()
            p.weight = bp.weight
            p.height = bp.height
            p.age = bp.age
            p.birthDate = bp.birthDate
            p.restingHeartRate = bp.restingHeartRate
            p.bodyFatPercent = bp.bodyFatPercent
            p.goalRaw = bp.goalRaw
            p.targetWeightKg = bp.targetWeightKg
            p.updatedAt = bp.updatedAt
            context.insert(p)
        }

        // 10. Restore Meals
        for bm in payload.mealEntries {
            let mealType = MealType(rawValue: bm.mealTypeRaw) ?? .snack
            let m = MealEntry(name: bm.name, calories: bm.calories, protein: bm.protein, fat: bm.fat, carbs: bm.carbs, grams: bm.grams, date: bm.date, mealType: mealType)
            if let uid = UUID(uuidString: bm.id) { m.id = uid }
            context.insert(m)
        }

        try context.save()
    }

    private func shouldExport() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: lastExportKey) as? Date else { return true }
        return Date().timeIntervalSince(last) >= exportInterval
    }

    private func saveLastExportDate() {
        UserDefaults.standard.set(Date(), forKey: lastExportKey)
    }

    private func signInAnonymouslyIfNeeded() async throws {
        if Auth.auth().currentUser != nil { return }
        _ = try await Auth.auth().signInAnonymously()
    }

    private func buildBackupPayload(context: ModelContext) throws -> Data {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let exportedAt = df.string(from: Date())

        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let workouts = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        let templates = (try? context.fetch(FetchDescriptor<WorkoutTemplate>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<FinanceAccount>())) ?? []
        let transactions = (try? context.fetch(FetchDescriptor<FinanceTransaction>())) ?? []
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        let habitEntries = (try? context.fetch(FetchDescriptor<HabitEntry>())) ?? []
        let todos = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        let goals = (try? context.fetch(FetchDescriptor<WeeklyGoal>())) ?? []
        let profiles = (try? context.fetch(FetchDescriptor<BodyProfile>())) ?? []
        let meals = (try? context.fetch(FetchDescriptor<MealEntry>())) ?? []

        let payload = BackupPayload(
            version: 1,
            exportedAt: exportedAt,
            exercises: exercises.map { BackupExercise(id: $0.id.uuidString, name: $0.name, bodyPart: $0.bodyPart, gifURL: $0.gifURL) },
            workouts: workouts.map { w in
                BackupWorkout(
                    id: w.id.uuidString,
                    name: w.name,
                    date: w.date,
                    startedAt: w.startedAt,
                    finishedAt: w.finishedAt,
                    exercises: w.workoutExercises.sorted { $0.order < $1.order }.map { we in
                        BackupWorkoutExercise(
                            id: we.id.uuidString,
                            order: we.order,
                            exerciseId: we.exercise.id.uuidString,
                            timerSeconds: we.timerSeconds,
                            sets: we.workoutSets.sorted { $0.order < $1.order }.map { s in
                                BackupWorkoutSet(id: s.id.uuidString, order: s.order, reps: s.reps, weight: s.weight, isCompleted: s.isCompleted, completedAt: s.completedAt)
                            }
                        )
                    }
                )
            },
            templates: templates.map { t in
                BackupTemplate(
                    id: t.id.uuidString,
                    name: t.name,
                    createdAt: t.createdAt,
                    exercises: t.exercises.sorted { $0.order < $1.order }.map { e in
                        BackupTemplateExercise(id: e.id.uuidString, order: e.order, exerciseName: e.exerciseName, bodyPart: e.bodyPart, defaultSets: e.defaultSets, defaultReps: e.defaultReps, defaultWeight: e.defaultWeight, timerSeconds: e.timerSeconds)
                    }
                )
            },
            financeAccounts: accounts.map { a in
                BackupFinanceAccount(id: a.id.uuidString, name: a.name, balance: a.balance, icon: a.icon, colorHex: a.colorHex, createdAt: a.createdAt)
            },
            financeTransactions: transactions.map { t in
                BackupFinanceTransaction(id: t.id.uuidString, name: t.name, amount: t.amount, categoryRaw: t.categoryRaw, typeRaw: t.typeRaw, date: t.date, accountID: t.accountID?.uuidString)
            },
            habits: habits.map { h in
                BackupHabit(id: h.id.uuidString, name: h.name, icon: h.icon, colorHex: h.colorHex, createdAt: h.createdAt, archived: h.archived)
            },
            habitEntries: habitEntries.compactMap { e in
                guard let hid = e.habit?.id else { return nil }
                return BackupHabitEntry(id: e.id.uuidString, date: e.date, habitId: hid.uuidString)
            },
            todos: todos.map { t in
                BackupTodo(id: t.id.uuidString, title: t.title, completed: t.completed, dueDate: t.dueDate, createdAt: t.createdAt, priority: t.priority, habitId: t.habit?.id.uuidString)
            },
            weeklyGoals: goals.map { g in
                BackupWeeklyGoal(id: g.id.uuidString, title: g.title, targetCount: g.targetCount, currentCount: g.currentCount, weekStart: g.weekStart, periodRaw: g.periodRaw, createdAt: g.createdAt)
            },
            bodyProfiles: profiles.map { p in
                BackupBodyProfile(weight: p.weight, height: p.height, age: p.effectiveAge, birthDate: p.birthDate, restingHeartRate: p.restingHeartRate, bodyFatPercent: p.bodyFatPercent, goalRaw: p.goalRaw, targetWeightKg: p.targetWeightKg, updatedAt: p.updatedAt)
            },
            mealEntries: meals.map { m in
                BackupMealEntry(id: m.id.uuidString, name: m.name, calories: m.calories, protein: m.protein, fat: m.fat, carbs: m.carbs, grams: m.grams, date: m.date, mealTypeRaw: m.mealTypeRaw)
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    private func upload(data: Data) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "FirebaseBackup", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]) }
        let ref = Storage.storage().reference().child(storagePath).child(uid).child("latest.json")
        
        return try await withCheckedThrowingContinuation { continuation in
            ref.putData(data, metadata: nil) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func download() async throws -> Data {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "FirebaseBackup", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]) }
        let ref = Storage.storage().reference().child(storagePath).child(uid).child("latest.json")
        
        return try await withCheckedThrowingContinuation { continuation in
            ref.getData(maxSize: 10 * 1024 * 1024) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(domain: "FirebaseBackup", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data found"]))
                }
            }
        }
    }
}
