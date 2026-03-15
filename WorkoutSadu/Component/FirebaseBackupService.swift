import Foundation
import SwiftData
import FirebaseAuth
import FirebaseStorage

// MARK: - Backup payload (Codable DTOs)

private struct BackupPayload: Codable {
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

private struct BackupExercise: Codable {
    let id: String
    let name: String
    let bodyPart: String
    let gifURL: String?
}

private struct BackupWorkoutSet: Codable {
    let id: String
    let order: Int
    let reps: Int
    let weight: Double
    let isCompleted: Bool
    let completedAt: Date?
}

private struct BackupWorkoutExercise: Codable {
    let id: String
    let order: Int
    let exerciseId: String
    let timerSeconds: Int?
    let sets: [BackupWorkoutSet]
}

private struct BackupWorkout: Codable {
    let id: String
    let name: String
    let date: Date
    let startedAt: Date?
    let finishedAt: Date?
    let exercises: [BackupWorkoutExercise]
}

private struct BackupTemplateExercise: Codable {
    let id: String
    let order: Int
    let exerciseName: String
    let bodyPart: String
    let defaultSets: Int
    let defaultReps: Int
    let defaultWeight: Double
    let timerSeconds: Int?
}

private struct BackupTemplate: Codable {
    let id: String
    let name: String
    let createdAt: Date
    let exercises: [BackupTemplateExercise]
}

private struct BackupFinanceAccount: Codable {
    let id: String
    let name: String
    let balance: Int
    let icon: String
    let colorHex: String
    let createdAt: Date
}

private struct BackupFinanceTransaction: Codable {
    let id: String
    let name: String
    let amount: Int
    let categoryRaw: String
    let typeRaw: String
    let date: Date
    let accountID: String?
}

private struct BackupHabit: Codable {
    let id: String
    let name: String
    let icon: String
    let colorHex: String
    let createdAt: Date
    let archived: Bool
}

private struct BackupHabitEntry: Codable {
    let id: String
    let date: Date
    let habitId: String
}

private struct BackupTodo: Codable {
    let id: String
    let title: String
    let completed: Bool
    let dueDate: Date?
    let createdAt: Date
    let priority: Int
    let habitId: String?
}

private struct BackupWeeklyGoal: Codable {
    let id: String
    let title: String
    let targetCount: Int
    let currentCount: Int
    let weekStart: Date
    let periodRaw: String
    let createdAt: Date
}

private struct BackupBodyProfile: Codable {
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

private struct BackupMealEntry: Codable {
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
        _ = try await ref.putDataAsync(data)
    }
}
