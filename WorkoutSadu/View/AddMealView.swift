import SwiftUI
import SwiftData
import UIKit

struct AddMealView: View {
    /// Если передан (например из FoodView при выборе дня), при открытии подставляется дата приёма пищи.
    var initialDate: Date?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [BodyProfile]

    @State private var foodText = ""
    @State private var parsedFoods: [ParsedFood] = []
    @State private var selectedMealType: MealType = .lunch
    @State private var mealDate: Date = Date()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didParse = false
    @State private var showImagePicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        inputCard
                        if isLoading { loadingCard }
                        if let err = errorMessage { errorCard(err) }
                        if didParse && !parsedFoods.isEmpty {
                            mealTypePicker
                            mealTimePicker
                            resultsCard
                            totalCard
                            saveButton
                        }
                    }
                    .dismissKeyboardOnTap()
                    .padding(16)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Добавить еду")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
            .sheet(isPresented: $showImagePicker) {
                FoodPhotoPicker { data in
                    showImagePicker = false
                    Task { await parseFood(from: data) }
                }
            }
            .onAppear {
                if let d = initialDate { mealDate = d }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Input

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ЧТО ВЫ СЪЕЛИ?")
            TextField("Например: 200г куриной грудки и рис", text: $foodText, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "#f0f0f5"))
                .padding(.horizontal, 16)

            Button {
                Task { await parseFood() }
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Рассчитать")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: "#ff5c3a"))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(foodText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            .opacity(foodText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Button {
                showImagePicker = true
            } label: {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("По фото")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Color(hex: "#ff5c3a"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: "#ff5c3a").opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isLoading)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .darkCard()
    }

    // MARK: - Loading

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Color(hex: "#ff5c3a"))
            Text("AI анализирует...")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .darkCard()
    }

    // MARK: - Error

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: "#ff5c3a"))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#f0f0f5"))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkCard(accentBorder: Color(hex: "#ff5c3a").opacity(0.3))
    }

    // MARK: - Meal Type Picker

    private var mealTypePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ПРИЁМ ПИЩИ")
            HStack(spacing: 8) {
                ForEach(MealType.allCases, id: \.rawValue) { type in
                    Button {
                        selectedMealType = type
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: type.icon)
                                .font(.system(size: 16))
                            Text(type.rawValue)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(selectedMealType == type ? .black : Color(hex: "#6b6b80"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selectedMealType == type ? Color(hex: "#ff5c3a") : Color(hex: "#1e1e28"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .darkCard()
    }

    // MARK: - Meal time

    private var mealTimePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ВРЕМЯ ПРИЁМА ПИЩИ")
            DatePicker("", selection: $mealDate, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .tint(Color(hex: "#ff5c3a"))
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .darkCard()
    }

    // MARK: - Results

    private var resultsCard: some View {
        VStack(spacing: 0) {
            sectionLabel("ПРОДУКТЫ")
            ForEach($parsedFoods) { $food in
                foodRow(food: $food)
                    .overlay(Divider().padding(.leading, 16), alignment: .bottom)
            }
        }
        .darkCard()
    }

    private func foodRow(food: Binding<ParsedFood>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(food.wrappedValue.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
                Spacer()
                Text("\(food.wrappedValue.calories) ккал")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: "#ff5c3a"))
            }

            HStack(spacing: 16) {
                macroChip("Б", food.wrappedValue.protein, Color(hex: "#5b8cff"))
                macroChip("Ж", food.wrappedValue.fat, Color(hex: "#ffb830"))
                macroChip("У", food.wrappedValue.carbs, Color(hex: "#3aff9e"))
                if food.wrappedValue.grams > 0 {
                    Text("\(Int(food.wrappedValue.grams))г")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func macroChip(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
            Text(String(format: "%.1f", value))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "#f0f0f5"))
        }
    }

    // MARK: - Total

    private var totalCard: some View {
        let totalCal = parsedFoods.reduce(0) { $0 + $1.calories }
        let totalP = parsedFoods.reduce(0.0) { $0 + $1.protein }
        let totalF = parsedFoods.reduce(0.0) { $0 + $1.fat }
        let totalC = parsedFoods.reduce(0.0) { $0 + $1.carbs }

        return VStack(spacing: 10) {
            sectionLabel("ИТОГО")
            Text("\(totalCal) ккал")
                .font(.custom("BebasNeue-Regular", size: 36))
                .foregroundStyle(Color(hex: "#ff5c3a"))

            HStack(spacing: 24) {
                macroColumn("Белки", totalP, Color(hex: "#5b8cff"))
                macroColumn("Жиры", totalF, Color(hex: "#ffb830"))
                macroColumn("Углеводы", totalC, Color(hex: "#3aff9e"))
            }
            .padding(.bottom, 14)
        }
        .darkCard(accentBorder: Color(hex: "#ff5c3a").opacity(0.2))
    }

    private func macroColumn(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.1f г", value))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        Button {
            saveMeals()
            dismiss()
        } label: {
            Text("Сохранить")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(hex: "#3aff9e"))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(hex: "#6b6b80"))
            .tracking(1)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func parseFood() async {
        isLoading = true
        errorMessage = nil
        do {
            let results = try await NutritionAIService.shared.parse(food: foodText, profile: profiles.first)
            parsedFoods = results
            didParse = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func parseFood(from imageData: Data) async {
        isLoading = true
        errorMessage = nil
        do {
            let results = try await NutritionAIService.shared.parse(imageData: imageData, profile: profiles.first)
            parsedFoods = results
            didParse = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func saveMeals() {
        for food in parsedFoods {
            let entry = MealEntry(
                name: food.name,
                calories: food.calories,
                protein: food.protein,
                fat: food.fat,
                carbs: food.carbs,
                grams: food.grams,
                date: mealDate,
                mealType: selectedMealType
            )
            context.insert(entry)
        }
        try? context.save()
    }
}

// MARK: - Photo picker for food (возвращает Data выбранного фото)

struct FoodPhotoPicker: UIViewControllerRepresentable {
    var onPick: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

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
        let parent: FoodPhotoPicker
        init(_ parent: FoodPhotoPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                parent.onPick(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
