import SwiftUI
import SwiftData

/// Выбор периода «от» и «до» для создания отчёта. Одна дата → отчёт за день.
struct CreateReportSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var dateFrom: Date = Date()
    @State private var dateTo: Date = Date()

    var onCreate: (Date, Date) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) {
                            Text("Выбери период")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color(hex: "#f0f0f5"))

                            VStack(alignment: .leading, spacing: 8) {
                                Text("ОТ")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(hex: "#6b6b80"))
                                    .tracking(1)
                                DatePicker("", selection: $dateFrom, displayedComponents: .date)
                                    .datePickerStyle(.graphical)
                                    .tint(Color(hex: "#ff5c3a"))
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("ДО")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(hex: "#6b6b80"))
                                    .tracking(1)
                                DatePicker("", selection: $dateTo, displayedComponents: .date)
                                    .datePickerStyle(.graphical)
                                    .tint(Color(hex: "#ff5c3a"))
                            }

                            if dateFrom > dateTo {
                                Text("Дата «до» раньше «от» — при создании они поменяются местами")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(hex: "#ffb830"))
                            }
                        }
                        .padding(24)
                        .padding(.bottom, 20)
                    }

                    Button {
                        var from = Calendar.current.startOfDay(for: dateFrom)
                        var to = Calendar.current.startOfDay(for: dateTo)
                        if from > to { swap(&from, &to) }
                        onCreate(from, to)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                            Text(periodLabel)
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "#ff5c3a"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(Color(hex: "#0e0e12"))
                }
            }
            .navigationTitle("Создать отчёт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var periodLabel: String {
        let from = Calendar.current.startOfDay(for: dateFrom)
        let to = Calendar.current.startOfDay(for: dateTo)
        if from == to {
            return "Отчёт за день"
        }
        let days = (Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0) + 1
        return "Отчёт за \(days) дн."
    }
}
