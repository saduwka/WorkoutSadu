import SwiftUI
import SwiftData

struct CreateWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var exercises: [WorkoutExercise] = []
    @State private var showExercisePicker = false
    
    let allExercises: [Exercise] = [
        Exercise(name: "Squat", bodyPart: "Legs"),
        Exercise(name: "Bench Press", bodyPart: "Chest"),
        Exercise(name: "Deadlift", bodyPart: "Back"),
        Exercise(name: "Bicep Curl", bodyPart: "Arms"),
        Exercise(name: "Shoulder Press", bodyPart: "Shoulders")
    ]

    var body: some View {
        Form {
            Section("Name") {
                TextField("Workout Name", text: $name)
            }
            Section("Exercises") {
                ForEach(exercises, id: \.id) { workoutExercise in
                    Text("\(workoutExercise.exercise.name) - \(workoutExercise.weight, specifier: "%.1f") kg x \(workoutExercise.reps)")
                }
                Button("Add Exercise") {
                    showExercisePicker = true
                }
            }
            Section {
                Button("Save Workout") {
                    saveWorkout()
                }
                .disabled(name.isEmpty || exercises.isEmpty)
            }
        }
        .navigationTitle("New workout")
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerView { workoutExercise in
                if !exercises.contains(where: { $0.id == workoutExercise.id }) {
                    exercises.append(workoutExercise)
                }
                showExercisePicker = false
            }
        }
    }

    private func saveWorkout() {
        guard !name.isEmpty, !exercises.isEmpty else { return }
        let workout = Workout(name: name)
        for workoutExercise in exercises {
            workout.exercises.append(workoutExercise)
        }
        context.insert(workout)
        saveWorkoutToJSON(workout: workout)
        dismiss()
    }
    
    private func saveWorkoutToJSON(workout: Workout) {
        struct CodableWorkout: Codable {
            var name: String
            var exercises: [CodableWorkoutExercise]
        }
        struct CodableWorkoutExercise: Codable {
            var exercise: CodableExercise
            var reps: Int
            var weight: Double
        }
        struct CodableExercise: Codable {
            var name: String
            var bodyPart: String
        }
        
        let codableExercises = workout.exercises.map { we in
            CodableWorkoutExercise(
                exercise: CodableExercise(name: we.exercise.name, bodyPart: we.exercise.bodyPart),
                reps: we.reps,
                weight: we.weight
            )
        }
        let codableWorkout = CodableWorkout(name: workout.name, exercises: codableExercises)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(codableWorkout)
            let filename = "workout_\(workout.name.replacingOccurrences(of: " ", with: "_")).json"
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
            try data.write(to: url)
            print("Workout saved to JSON at: \(url)")
        } catch {
            print("Failed to save workout to JSON: \(error.localizedDescription)")
        }
    }
}
