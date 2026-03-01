import SwiftUI
import SwiftData

struct FinanceHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FinanceTransaction.date, order: .reverse) private var allTransactions: [FinanceTransaction]

    @State private var searchText = ""
    @State private var selectedCategory: FinanceCategory?
    @State private var selectedType: FinanceType?
    @State private var showFilters = false

    private var filtered: [FinanceTransaction] {
        var list = allTransactions
        if let cat = selectedCategory { list = list.filter { $0.category == cat } }
        if let type = selectedType { list = list.filter { $0.type == type } }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter { $0.name.lowercased().contains(q) }
        }
        return list
    }

    private var groupedByDate: [(String, [FinanceTransaction])] {
        let df = DateFormatter()
        df.dateFormat = "d MMMM yyyy"
        df.locale = Locale(identifier: "ru_RU")

        var dict: [String: [FinanceTransaction]] = [:]
        var order: [String] = []
        for tx in filtered {
            let key = df.string(from: tx.date)
            if dict[key] == nil { order.append(key) }
            dict[key, default: []].append(tx)
        }
        return order.map { ($0, dict[$0]!) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                    if showFilters { filterBar }
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if filtered.isEmpty {
                                emptyView
                            } else {
                                ForEach(groupedByDate, id: \.0) { date, txs in
                                    dateHeader(date, txs)
                                    ForEach(txs) { tx in
                                        transactionRow(tx)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 40)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle("ИСТОРИЯ")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color(hex: "#6b6b80"))
                TextField("Поиск", text: $searchText)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(hex: "#6b6b80"))
                    }
                }
            }
            .padding(10)
            .background(Color(hex: "#1a1a24"))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button { withAnimation { showFilters.toggle() } } label: {
                Image(systemName: "line.3.horizontal.decrease.circle\(showFilters ? ".fill" : "")")
                    .font(.system(size: 22))
                    .foregroundStyle(showFilters ? Color(hex: "#ff5c3a") : Color(hex: "#6b6b80"))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK: - Filters

    private var filterBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    filterChip("Все типы", selectedType == nil) { selectedType = nil }
                    filterChip("Расходы", selectedType == .expense) { selectedType = .expense }
                    filterChip("Доходы", selectedType == .income) { selectedType = .income }
                }
                .padding(.horizontal, 16)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    filterChip("Все", selectedCategory == nil) { selectedCategory = nil }
                    ForEach(FinanceCategory.allCases, id: \.self) { cat in
                        filterChip(cat.rawValue, selectedCategory == cat) { selectedCategory = cat }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 6)
    }

    private func filterChip(_ label: String, _ active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? .white : Color(hex: "#6b6b80"))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(active ? Color(hex: "#ff5c3a") : Color(hex: "#1a1a24"))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date header

    private func dateHeader(_ date: String, _ txs: [FinanceTransaction]) -> some View {
        HStack {
            Text(date)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
            Spacer()
            let dayTotal = txs.reduce(0) { $0 + ($1.type == .expense ? -$1.amount : $1.amount) }
            Text(formatSigned(dayTotal))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(dayTotal >= 0 ? Color(hex: "#3aff9e") : Color(hex: "#ff5c3a"))
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
    }

    // MARK: - Row

    private func transactionRow(_ tx: FinanceTransaction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tx.category.icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: tx.category.color))
                .frame(width: 36, height: 36)
                .background(Color(hex: tx.category.color).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
                    .lineLimit(1)
                Text(tx.category.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#6b6b80"))
            }
            Spacer()
            Text("\(tx.type == .income ? "+" : "-")\(formatAmount(tx.amount))")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(tx.type == .income ? Color(hex: "#3aff9e") : Color(hex: "#f0f0f5"))

            Button { context.delete(tx); try? context.save() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#6b6b80").opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.title).foregroundStyle(Color(hex: "#6b6b80"))
            Text("Нет транзакций").font(.system(size: 14)).foregroundStyle(Color(hex: "#6b6b80"))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Helpers

    private func formatAmount(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formatSigned(_ value: Int) -> String {
        let prefix = value >= 0 ? "+" : "-"
        return "\(prefix)\(formatAmount(abs(value)))"
    }
}
