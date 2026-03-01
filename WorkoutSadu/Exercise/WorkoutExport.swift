import Foundation
import SwiftData

// MARK: - Export

struct WorkoutExport: Codable {
    let name: String
    let date: Date
    let startedAt: Date?
    let finishedAt: Date?
    let exercises: [WorkoutExerciseExport]

    init(from workout: Workout) {
        self.name = workout.name
        self.date = workout.date
        self.startedAt = workout.startedAt
        self.finishedAt = workout.finishedAt
        self.exercises = workout.workoutExercises.map { WorkoutExerciseExport(from: $0) }
    }
}

struct WorkoutExerciseExport: Codable {
    let name: String
    let bodyPart: String
    let sets: [WorkoutSetExport]
    let distance: Double?
    let cardioTimeSeconds: Int?
    let note: String?
    let supersetGroup: Int?

    init(from we: WorkoutExercise) {
        self.name = we.exercise.name
        self.bodyPart = we.exercise.bodyPart
        self.sets = we.workoutSets
            .sorted { $0.order < $1.order }
            .map { WorkoutSetExport(from: $0) }
        self.distance = we.distance
        self.cardioTimeSeconds = we.cardioTimeSeconds
        self.note = we.note
        self.supersetGroup = we.supersetGroup
    }
}

struct WorkoutSetExport: Codable {
    let order: Int
    let reps: Int
    let weight: Double
    let isCompleted: Bool

    init(from set: WorkoutSet) {
        self.order = set.order
        self.reps = set.reps
        self.weight = set.weight
        self.isCompleted = set.isCompleted
    }
}

// MARK: - Template Export / Import

struct TemplateExport: Codable {
    let name: String
    let exercises: [TemplateExerciseExport]

    init(from template: WorkoutTemplate) {
        self.name = template.name
        self.exercises = template.exercises
            .sorted { $0.order < $1.order }
            .map { TemplateExerciseExport(from: $0) }
    }
}

struct TemplateExerciseExport: Codable {
    let order: Int
    let exerciseName: String
    let bodyPart: String
    let timerSeconds: Int?
    let defaultSets: Int
    let defaultReps: Int
    let defaultWeight: Double

    init(from te: TemplateExercise) {
        self.order = te.order
        self.exerciseName = te.exerciseName
        self.bodyPart = te.bodyPart
        self.timerSeconds = te.timerSeconds
        self.defaultSets = te.defaultSets
        self.defaultReps = te.defaultReps
        self.defaultWeight = te.defaultWeight
    }
}

struct TemplateImporter {
    static func importJSON(from url: URL, into context: ModelContext) throws -> WorkoutTemplate {
        let data = try Data(contentsOf: url)

        if let single = try? JSONDecoder().decode(TemplateExport.self, from: data) {
            return createTemplate(from: single, in: context)
        }

        let array = try JSONDecoder().decode([TemplateExport].self, from: data)
        guard let first = array.first else {
            throw NSError(domain: "TemplateImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Пустой файл шаблона"])
        }
        for item in array.dropFirst() {
            _ = createTemplate(from: item, in: context)
        }
        return createTemplate(from: first, in: context)
    }

    static func exportJSON(templates: [WorkoutTemplate]) throws -> Data {
        let exports = templates.map { TemplateExport(from: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(exports)
    }

    private static func createTemplate(from export: TemplateExport, in context: ModelContext) -> WorkoutTemplate {
        let template = WorkoutTemplate(name: export.name)
        context.insert(template)

        for ex in export.exercises {
            let te = TemplateExercise(
                order: ex.order,
                exerciseName: ex.exerciseName,
                bodyPart: ex.bodyPart,
                timerSeconds: ex.timerSeconds,
                defaultSets: ex.defaultSets,
                defaultReps: ex.defaultReps,
                defaultWeight: ex.defaultWeight
            )
            template.exercises.append(te)
        }

        return template
    }
}

// MARK: - Legacy Format (flat entries)

private struct LegacyWorkout: Codable {
    let name: String
    let date: Double
    let exercises: [LegacyExerciseEntry]
}

private struct LegacyExerciseEntry: Codable {
    let name: String
    let bodyPart: String
    let reps: Int
    let sets: Int
    let weight: Double
}

// MARK: - Import

struct WorkoutImporter {
    static func importJSON(from url: URL, into context: ModelContext) throws -> Workout {
        let data = try Data(contentsOf: url)

        if let workout = try? importCurrentFormat(data: data, context: context) {
            return workout
        }

        return try importLegacyFormat(data: data, context: context)
    }

    private static func importCurrentFormat(data: Data, context: ModelContext) throws -> Workout {
        let decoded = try JSONDecoder().decode(WorkoutExport.self, from: data)

        let workout = Workout(name: decoded.name, date: decoded.date)
        workout.startedAt = decoded.startedAt
        workout.finishedAt = decoded.finishedAt
        context.insert(workout)

        for (index, ex) in decoded.exercises.enumerated() {
            let exercise = Exercise.findOrCreate(name: ex.name, bodyPart: ex.bodyPart, in: context)
            let we = WorkoutExercise(exercise: exercise)
            we.distance = ex.distance
            we.cardioTimeSeconds = ex.cardioTimeSeconds
            we.note = ex.note
            we.supersetGroup = ex.supersetGroup
            we.order = index
            context.insert(we)

            for s in ex.sets {
                let ws = WorkoutSet(order: s.order, reps: s.reps, weight: s.weight)
                ws.isCompleted = s.isCompleted
                context.insert(ws)
                we.workoutSets.append(ws)
            }

            workout.workoutExercises.append(we)
        }

        return workout
    }

    private static func importLegacyFormat(data: Data, context: ModelContext) throws -> Workout {
        let legacy = try JSONDecoder().decode(LegacyWorkout.self, from: data)

        let date = Date(timeIntervalSinceReferenceDate: legacy.date)
        let workout = Workout(name: legacy.name, date: date)
        context.insert(workout)

        var grouped: [(key: String, entries: [LegacyExerciseEntry])] = []
        var seen: [String: Int] = [:]

        for entry in legacy.exercises {
            let key = entry.name.trimmingCharacters(in: .whitespaces)
            if let idx = seen[key] {
                grouped[idx].entries.append(entry)
            } else {
                seen[key] = grouped.count
                grouped.append((key: key, entries: [entry]))
            }
        }

        for group in grouped {
            let first = group.entries[0]
            let exercise = Exercise.findOrCreate(
                name: group.key,
                bodyPart: first.bodyPart,
                in: context
            )
            let we = WorkoutExercise(exercise: exercise)
            context.insert(we)

            for (i, entry) in group.entries.enumerated() {
                let ws = WorkoutSet(order: i + 1, reps: entry.reps, weight: entry.weight)
                ws.isCompleted = true
                ws.completedAt = date
                context.insert(ws)
                we.workoutSets.append(ws)
            }

            workout.workoutExercises.append(we)
        }

        return workout
    }
}
