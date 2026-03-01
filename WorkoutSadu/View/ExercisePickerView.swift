import SwiftUI

struct ExercisePickerView: View {
    let bodyParts = ["Legs", "Chest", "Back", "Arms", "Shoulders"]
    @State private var selectedBodyPart = "Legs"
    @State private var exerciseName = ""
    @State private var weight = 0.0
    @State private var reps = 1
    @State private var showImagePicker = false
    @State private var trainerImage: UIImage?
    let onSelect: (WorkoutExercise) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Picker("Body Part", selection: $selectedBodyPart) {
                    ForEach(bodyParts, id: \.self) { part in
                        Text(part)
                    }
                }
                TextField("Exercise name", text: $exerciseName)
                Stepper(value: $weight, in: 0...500, step: 0.5) {
                    Text("Weight: \(weight, specifier: "%.1f") kg")
                }
                Stepper(value: $reps, in: 1...100) {
                    Text("Reps: \(reps)")
                }
                Button("Take Photo") {
                    showImagePicker = true
                }
                Button("Add") {
                    let exercise = Exercise(name: exerciseName, bodyPart: selectedBodyPart)
                    let workoutExercise = WorkoutExercise(exercise: exercise, reps: reps, weight: weight)
                    onSelect(workoutExercise)
                    dismiss()
                }
                .disabled(exerciseName.isEmpty)
            }
            .navigationTitle("Select Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $trainerImage)
            }
        }
    }
}
