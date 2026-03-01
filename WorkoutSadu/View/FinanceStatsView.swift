import SwiftUI
import SwiftData
import Charts

struct FinanceStatsView: View {
    @Query(sort: \FinanceTransaction.date, order: .reverse) private var allTransactions: [FinanceTransaction]
    @State private var selectedPeriod: StatsPeriod = .month

    enum StatsPeriod: String, CaseIterable {
        case week = "Неделя"
        case month = "Месяц"
        case threeMonths = "3 месяца"
        case all = "Всё"

        var startDate: Date? {
            let c = Calendar.current
            switch self {
            case .week:        return c.date(byAdding: .day, value: -7, to: .now)
            case .month:       return c.date(byAdding: .month, value: -1, to: .now)
            case .threeMonths: return c.date(byAdding: .month, value: -3, to: .now)
            case .all:         return nil
            }
        }
    }

    private var filtered: [FinanceTransaction] {
        guard let s = selectedPeriod.startDate else { return allTransactions }
        return allTransactions.filter { $0.date >= s }
    }

    private var totalIncome: Int { filtered.filter { $0.type == .income }.reduce(0) { $0 + $1.amount } }
    private var totalExpense: Int { filtered.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount } }

    private var expensesByCategory: [(FinanceCategory, Int)] {
        var dict: [FinanceCategory: Int] = [:]
        for tx in filtered where tx.type == .expense {
            dict[tx.category, default: 0] += tx.amount
        }
        return dict.sorted { $0.value > $1.value }
    }

    private struct DayPoint: Identifiable {
        let id = UUID()
        let date: Date
        let income: Int
        let expense: Int
    }

    private var dailyData: [DayPoint] {
        let cal = Calendar.current
        let days: Int
        switch selectedPeriod {
        case .week: days = 7
        case .month: days = 30
        case .threeMonths: days = 90
        case .all: days = 30
        }

        return (0..<days).compactMap { offset -> DayPoint? in
            guard let day = cal.date(byAdding: .day, value: -offset, to: .now) else { return nil }
            let start = cal.startOfDay(for: day)
            guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
            let dayTx = filtered.filter { $0.date >= start && $0.date < end }
            let inc = dayTx.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            let exp = dayTx.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
            return DayPoint(date: start, income: inc, expense: exp)
        }.reversed()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        periodPicker
                        summaryCards
                        chartCard
                        categoriesCard
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("СТАТИСТИКА")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Period

    private var periodPicker: some View {
        Picker("", selection: $selectedPeriod) {
            ForEach(StatsPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Summary

    private var summaryCards: some View {
        HStack(spacing: 10) {
            statMini("Доходы", totalIncome, Color(hex: "#3aff9e"))
            statMini("Расходы", totalExpense, Color(hex: "#ff5c3a"))
            statMini("Баланс", totalIncome - totalExpense, totalIncome >= totalExpense ? Color(hex: "#3aff9e") : Color(hex: "#ff5c3a"))
        }
    }

    private func statMini(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(formatAmount(abs(value)))
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .darkCard()
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ДИНАМИКА")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)

            if dailyData.isEmpty {
                Text("Нет данных")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                Chart {
                    ForEach(dailyData) { pt in
                        if pt.expense > 0 {
                            BarMark(
                                x: .value("Дата", pt.date, unit: .day),
                                y: .value("Расход", pt.expense)
                            )
                            .foregroundStyle(Color(hex: "#ff5c3a").opacity(0.7))
                        }
                        if pt.income > 0 {
                            BarMark(
                                x: .value("Дата", pt.date, unit: .day),
                                y: .value("Доход", pt.income)
                            )
                            .foregroundStyle(Color(hex: "#3aff9e").opacity(0.7))
                        }
                    }
                }
                .frame(height: 160)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: selectedPeriod == .week ? 1 : 7)) { value in
                        AxisValueLabel(format: .dateTime.day())
                            .foregroundStyle(Color(hex: "#6b6b80"))
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(Color(hex: "#1a1a24"))
                        AxisValueLabel().foregroundStyle(Color(hex: "#6b6b80"))
                    }
                }
            }
        }
        .padding(14)
        .darkCard()
    }

    // MARK: - Categories

    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("РАСХОДЫ ПО КАТЕГОРИЯМ")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)

            if expensesByCategory.isEmpty {
                Text("Нет расходов")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                ForEach(expensesByCategory, id: \.0) { cat, amount in
                    categoryRow(cat, amount)
                }
            }
        }
        .padding(14)
        .darkCard()
    }

    private func categoryRow(_ cat: FinanceCategory, _ amount: Int) -> some View {
        let pct = totalExpense > 0 ? Double(amount) / Double(totalExpense) : 0

        return HStack(spacing: 12) {
            Image(systemName: cat.icon)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: cat.color))
                .frame(width: 28, height: 28)
                .background(Color(hex: cat.color).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(cat.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    Spacer()
                    Text(formatAmount(amount))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    Text("\(Int(pct * 100))%")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                        .frame(width: 32, alignment: .trailing)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#1a1a24"))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: cat.color))
                            .frame(width: geo.size.width * pct, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func formatAmount(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
