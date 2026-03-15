import SwiftUI
import SwiftData

/// Редактирование записи о еде: название, КБЖУ, тип приёма, дата и время.
struct EditMealSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var meal: MealEntry

    @State private var name: String = ""
    @State private var caloriesText: String = ""
    @State private var proteinText: String = ""
    @State private var fatText: String = ""
    @State private var carbsText: String = ""
    @State private var mealDate: Date = Date()
    @State private var selectedMealType: MealType = .snack

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("БЛЮДО")
                            TextField("Название", text: $name)
                                .font(.system(size: 16))
                                .foregroundStyle(Color(hex: "#f0f0f5"))
                                .padding(12)
                                .background(Color(hex: "#1a1a24"))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("ВРЕМЯ ПРИЁМА ПИЩИ")
                            DatePicker("", selection: $mealDate, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                                .tint(Color(hex: "#ff5c3a"))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("ТИП ПРИЁМА")
                            HStack(spacing: 8) {
                                ForEach(MealType.allCases, id: \.rawValue) { type in
                                    Button {
                                        selectedMealType = type
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: type.icon)
                                                .font(.system(size: 14))
                                            Text(type.rawValue)
                                                .font(.system(size: 9, weight: .medium))
                                        }
                                        .foregroundStyle(selectedMealType == type ? .black : Color(hex: "#6b6b80"))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(selectedMealType == type ? Color(hex: "#ff5c3a") : Color(hex: "#1e1e28"))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("КБЖУ")
                            HStack(spacing: 10) {
                                macroField("Ккал", $caloriesText)
                                macroField("Б", $proteinText)
                                macroField("Ж", $fatText)
                                macroField("У", $carbsText)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        save()
                        dismiss()
                    }
                    .foregroundStyle(Color(hex: "#ff5c3a"))
                }
            }
            .onAppear {
                name = meal.name
                caloriesText = "\(meal.calories)"
                proteinText = String(format: "%.0f", meal.protein)
                fatText = String(format: "%.0f", meal.fat)
                carbsText = String(format: "%.0f", meal.carbs)
                mealDate = meal.date
                selectedMealType = meal.mealType
            }
        }
        .preferredColorScheme(.dark)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(hex: "#6b6b80"))
            .tracking(1)
    }

    private func macroField(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: "#f0f0f5"))
                .padding(10)
                .background(Color(hex: "#1a1a24"))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func save() {
        meal.name = name.trimmingCharacters(in: .whitespaces)
        meal.calories = Int(caloriesText.filter { $0.isNumber }) ?? 0
        meal.protein = Double(proteinText.replacingOccurrences(of: ",", with: ".")) ?? 0
        meal.fat = Double(fatText.replacingOccurrences(of: ",", with: ".")) ?? 0
        meal.carbs = Double(carbsText.replacingOccurrences(of: ",", with: ".")) ?? 0
        meal.date = mealDate
        meal.mealType = selectedMealType
    }
}
