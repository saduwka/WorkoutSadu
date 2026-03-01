import SwiftUI
import UserNotifications

struct ExerciseView: View {
    var workoutExercise: WorkoutExercise
    @State private var showEditView = false
    
    var body: some View {
        Form {
            Section("Exercise") {
                Text(workoutExercise.exercise.name)
                    .font(.headline)
                Text("Body part: \(workoutExercise.exercise.bodyPart)")
                    .font(.subheadline)
            }
            
            Section("Reps & Weight") {
                Text("Reps: \(workoutExercise.reps)")
                Text("Weight: \(workoutExercise.weight, specifier: "%.1f") kg")
            }
            
            Section("Photo") {
                if let data = workoutExercise.photo, let uiImage = UIImage(data: data) {
                    VStack {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .navigationTitle(workoutExercise.exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") {
                showEditView = true
            }
        }
        .sheet(isPresented: $showEditView) {
            ExerciseEditView(workoutExercise: workoutExercise)
        }
    }
}
