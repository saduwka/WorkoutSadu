import SwiftUI
import SwiftData

/// Обёртка для показа sheet редактирования по item.
private struct TransactionEditItem: Identifiable {
    let transaction: FinanceTransaction
    var id: UUID { transaction.id }
}

struct FinanceHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FinanceTransaction.date, order: .reverse) private var allTransactions: [FinanceTransaction]
    @Query(sort: \FinanceAccount.createdAt) private var accounts: [FinanceAccount]

    @State private var searchText = ""
    @State private var selectedCategory: FinanceCategory?
    @State private var selectedType: FinanceType?
    @State private var showFilters = false
    @State private var editingItem: TransactionEditItem?

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
                .dismissKeyboardOnTap()
            }
            .navigationTitle("ИСТОРИЯ")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingItem) { item in
                EditTransactionSheet(transaction: item.transaction, accounts: accounts)
            }
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
            let dayTotal = txs
                .filter { $0.category != .transfers }
                .reduce(0) { $0 + ($1.type == .expense ? -$1.amount : $1.amount) }
            Text(formatSigned(dayTotal))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(dayTotal >= 0 ? Color(hex: "#3aff9e") : Color(hex: "#ff5c3a"))
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
    }

    // MARK: - Row

    private func transactionRow(_ tx: FinanceTransaction) -> some View {
        Button {
            editingItem = TransactionEditItem(transaction: tx)
        } label: {
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

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "#6b6b80").opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                context.delete(tx)
                try? context.save()
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
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

// MARK: - Edit Transaction Sheet

private struct EditTransactionSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var transaction: FinanceTransaction
    let accounts: [FinanceAccount]
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        typeSelector
                        amountCard
                        if !accounts.isEmpty { accountPicker }
                        detailsCard
                        categoryCard
                        deleteButton
                    }
                    .dismissKeyboardOnTap()
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("РЕДАКТИРОВАТЬ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        try? context.save()
                        dismiss()
                    }
                    .foregroundStyle(Color(hex: "#ff5c3a"))
                }
            }
            .onAppear {
                if transaction.accountID == nil, let first = accounts.first { transaction.accountID = first.id }
            }
            .alert("Удалить транзакцию?", isPresented: $showDeleteConfirm) {
                Button("Отмена", role: .cancel) {}
                Button("Удалить", role: .destructive) {
                    context.delete(transaction)
                    try? context.save()
                    dismiss()
                }
            } message: {
                Text("Запись «\(transaction.name)» будет удалена из истории. Отменить действие нельзя.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var deleteButton: some View {
        Button(role: .destructive) { showDeleteConfirm = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                Text("Удалить транзакцию")
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color(hex: "#ff5c3a"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private var typeSelector: some View {
        Picker("", selection: $transaction.type) {
            ForEach(FinanceType.allCases, id: \.self) { t in
                Text(t.rawValue).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: transaction.type) {
            if transaction.type == .income { transaction.category = .income }
            else if transaction.category == .income { transaction.category = .other }
        }
    }

    private var amountCard: some View {
        VStack(spacing: 8) {
            Text("СУММА")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)
            TextField("0", value: $transaction.amount, format: .number)
                .keyboardType(.numberPad)
                .font(.custom("BebasNeue-Regular", size: 48))
                .foregroundStyle(transaction.type == .income ? Color(hex: "#3aff9e") : Color(hex: "#f0f0f5"))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .darkCard()
    }

    private var accountPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("СЧЁТ")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)
                .padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(accounts) { acc in
                        Button {
                            transaction.accountID = acc.id
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: acc.icon)
                                    .font(.system(size: 12))
                                Text(acc.name)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(transaction.accountID == acc.id ? .white : Color(hex: "#6b6b80"))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(transaction.accountID == acc.id ? Color(hex: acc.colorHex) : Color(hex: "#1a1a24"))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .darkCard()
    }

    private var detailsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "pencil").foregroundStyle(Color(hex: "#6b6b80"))
                TextField("Название", text: $transaction.name)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
            }
            .padding(14)
            .background(Color(hex: "#1a1a24"))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            DatePicker("Дата", selection: $transaction.date, displayedComponents: .date)
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: "#f0f0f5"))
                .tint(Color(hex: "#ff5c3a"))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(hex: "#1a1a24"))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .darkCard()
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("КАТЕГОРИЯ")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)
                .padding(.horizontal, 4)

            let categories = transaction.type == .income
                ? [FinanceCategory.income]
                : FinanceCategory.allCases.filter { $0 != .income }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    Button {
                        transaction.category = cat
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(transaction.category == cat ? Color(hex: cat.color) : Color(hex: "#6b6b80"))
                            Text(cat.rawValue)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(transaction.category == cat ? Color(hex: "#f0f0f5") : Color(hex: "#6b6b80"))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(transaction.category == cat ? Color(hex: cat.color).opacity(0.15) : Color(hex: "#1a1a24"))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(transaction.category == cat ? Color(hex: cat.color).opacity(0.4) : .clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .darkCard()
    }
}
