import SwiftUI
import SwiftData
import Charts

struct FinanceView: View {
    @State private var section: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker

            Group {
                switch section {
                case 0:  FinanceOverviewView()
                case 1:  FinanceHistoryView()
                case 2:  FinanceStatsView()
                default: FinanceOverviewView()
                }
            }
        }
        .background(Color(hex: "#0e0e12"))
    }

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            let tabs = [
                ("Обзор", "creditcard.fill"),
                ("История", "list.bullet"),
                ("Статистика", "chart.pie.fill")
            ]

            ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { section = i }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.1)
                            .font(.system(size: 14))
                        Text(tab.0)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(section == i ? Color(hex: "#ff5c3a") : Color(hex: "#6b6b80"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .background(Color(hex: "#0e0e12"))
    }
}

// MARK: - Overview

struct FinanceOverviewView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FinanceTransaction.date, order: .reverse) private var allTransactions: [FinanceTransaction]
    @Query(sort: \FinanceAccount.createdAt) private var accounts: [FinanceAccount]

    @State private var showAddManual = false
    @State private var showVoiceInput = false
    @State private var showReceiptCapture = false
    @State private var showAddAccount = false
    @State private var editingAccount: FinanceAccount?

    private var todayTransactions: [FinanceTransaction] {
        let cal = Calendar.current
        return allTransactions.filter { cal.isDateInToday($0.date) }
    }

    private var todayIncome: Int { todayTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount } }
    private var todayExpense: Int { todayTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount } }

    private var totalBalance: Int {
        let accBal = accounts.reduce(0) { $0 + accountBalance($1) }
        let unaccounted = allTransactions.filter { $0.accountID == nil }
        let uInc = unaccounted.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let uExp = unaccounted.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        return accBal + uInc - uExp
    }

    private func accountBalance(_ account: FinanceAccount) -> Int {
        let txs = allTransactions.filter { $0.accountID == account.id }
        let income = txs.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let expense = txs.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        return account.balance + income - expense
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        accountsSection
                        todaySummary
                        inputButtons
                        todayTransactionsCard
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("ФИНАНСЫ")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAddManual) { FinanceAddTransactionView() }
            .sheet(isPresented: $showVoiceInput) { VoiceInputView() }
            .sheet(isPresented: $showReceiptCapture) { ReceiptCaptureView() }
            .sheet(isPresented: $showAddAccount) { AddAccountSheet() }
            .sheet(item: $editingAccount) { acc in EditAccountSheet(account: acc) }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Accounts

    private var accountsSection: some View {
        VStack(spacing: 10) {
            if accounts.count > 1 || !allTransactions.filter({ $0.accountID == nil }).isEmpty {
                VStack(spacing: 6) {
                    Text("ОБЩИЙ БАЛАНС")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                        .tracking(1)
                    Text(formatSigned(totalBalance))
                        .font(.custom("BebasNeue-Regular", size: 44))
                        .foregroundStyle(totalBalance >= 0 ? Color(hex: "#3aff9e") : Color(hex: "#ff5c3a"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .darkCard()
            }

            ForEach(accounts) { account in
                accountCard(account)
            }

            Button { showAddAccount = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("Добавить счёт")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(Color(hex: "#6b6b80"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(hex: "#1a1a24").opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(hex: "#6b6b80").opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [6]))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func accountCard(_ account: FinanceAccount) -> some View {
        Button { editingAccount = account } label: {
            HStack(spacing: 12) {
                Image(systemName: account.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: account.colorHex))
                    .frame(width: 40, height: 40)
                    .background(Color(hex: account.colorHex).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    Text("начальный: \(formatAmount(account.balance))")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }

                Spacer()

                let bal = accountBalance(account)
                Text(formatSigned(bal))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(bal >= 0 ? Color(hex: "#3aff9e") : Color(hex: "#ff5c3a"))
            }
            .padding(14)
            .darkCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Today summary

    private var todaySummary: some View {
        HStack(spacing: 10) {
            summaryMini("Доходы", todayIncome, "arrow.down.circle.fill", Color(hex: "#3aff9e"))
            summaryMini("Расходы", todayExpense, "arrow.up.circle.fill", Color(hex: "#ff5c3a"))
        }
    }

    private func summaryMini(_ title: String, _ amount: Int, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(formatAmount(amount))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(hex: "#f0f0f5"))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.system(size: 11)).foregroundStyle(Color(hex: "#6b6b80"))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .darkCard()
    }

    // MARK: - Input buttons

    private var inputButtons: some View {
        HStack(spacing: 10) {
            inputButton("Записать", "mic.fill", Color(hex: "#5b8cff")) { showVoiceInput = true }
            inputButton("Добавить", "plus.circle.fill", Color(hex: "#ff5c3a")) { showAddManual = true }
            inputButton("Чек", "doc.text.viewfinder", Color(hex: "#ffb830")) { showReceiptCapture = true }
        }
    }

    private func inputButton(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .darkCard(accentBorder: color.opacity(0.2))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Today transactions

    private var todayTransactionsCard: some View {
        VStack(spacing: 0) {
            sectionLabel("СЕГОДНЯ")

            if todayTransactions.isEmpty {
                Text("Нет транзакций за сегодня")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(todayTransactions) { tx in
                    transactionRow(tx)
                        .overlay(Divider().padding(.leading, 50), alignment: .bottom)
                }
            }
        }
        .darkCard()
    }

    private func transactionRow(_ tx: FinanceTransaction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tx.category.icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: tx.category.color))
                .frame(width: 32, height: 32)
                .background(Color(hex: tx.category.color).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(tx.category.rawValue)
                    if let accName = accounts.first(where: { $0.id == tx.accountID })?.name {
                        Text("·")
                        Text(accName)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "#6b6b80"))
            }
            Spacer()
            Text("\(tx.type == .income ? "+" : "-")\(formatAmount(tx.amount))")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(tx.type == .income ? Color(hex: "#3aff9e") : Color(hex: "#f0f0f5"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(hex: "#6b6b80"))
            .tracking(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func formatAmount(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
    }

    private func formatSigned(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        let abs = f.string(from: NSNumber(value: Swift.abs(value))) ?? "\(Swift.abs(value))"
        return value < 0 ? "-\(abs)" : abs
    }
}

// MARK: - Add Account Sheet

struct AddAccountSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var balanceText = ""
    @State private var selectedIcon = "creditcard.fill"
    @State private var selectedColor = "#5b8cff"

    private let icons = [
        "creditcard.fill", "banknote.fill", "wallet.bifold.fill",
        "building.columns.fill", "dollarsign.circle.fill", "bitcoinsign.circle.fill",
        "gift.fill", "star.fill"
    ]

    private let colors = [
        "#5b8cff", "#3aff9e", "#ff5c3a", "#ffb830",
        "#a855f7", "#f472b6", "#6366f1", "#6b7280"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        HStack {
                            Image(systemName: "tag.fill").foregroundStyle(Color(hex: "#6b6b80"))
                            TextField("Название счёта", text: $name)
                                .font(.system(size: 16))
                                .foregroundStyle(Color(hex: "#f0f0f5"))
                        }
                        .padding(14)
                        .darkCard()

                        VStack(spacing: 8) {
                            Text("НАЧАЛЬНЫЙ БАЛАНС")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .tracking(1)
                            TextField("0", text: $balanceText)
                                .keyboardType(.numberPad)
                                .font(.custom("BebasNeue-Regular", size: 42))
                                .foregroundStyle(Color(hex: "#f0f0f5"))
                                .multilineTextAlignment(.center)
                        }
                        .padding(16)
                        .darkCard()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("ИКОНКА")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .tracking(1)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                                ForEach(icons, id: \.self) { ic in
                                    Button { selectedIcon = ic } label: {
                                        Image(systemName: ic)
                                            .font(.system(size: 18))
                                            .foregroundStyle(selectedIcon == ic ? Color(hex: selectedColor) : Color(hex: "#6b6b80"))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(selectedIcon == ic ? Color(hex: selectedColor).opacity(0.15) : Color(hex: "#1a1a24"))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(14)
                        .darkCard()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("ЦВЕТ")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .tracking(1)
                            HStack(spacing: 8) {
                                ForEach(colors, id: \.self) { c in
                                    Button { selectedColor = c } label: {
                                        Circle()
                                            .fill(Color(hex: c))
                                            .frame(width: 32, height: 32)
                                            .overlay(
                                                Circle().stroke(.white, lineWidth: selectedColor == c ? 2 : 0)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(14)
                        .darkCard()

                        Button {
                            let acc = FinanceAccount(
                                name: name.isEmpty ? "Счёт" : name,
                                balance: Int(balanceText) ?? 0,
                                icon: selectedIcon,
                                colorHex: selectedColor
                            )
                            context.insert(acc)
                            try? context.save()
                            dismiss()
                        } label: {
                            Text("Создать")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(name.isEmpty ? Color(hex: "#6b6b80").opacity(0.4) : Color(hex: "#ff5c3a"))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(name.isEmpty)
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
            .navigationTitle("НОВЫЙ СЧЁТ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }.foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Edit Account Sheet

struct EditAccountSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var account: FinanceAccount

    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        HStack {
                            Image(systemName: "tag.fill").foregroundStyle(Color(hex: "#6b6b80"))
                            TextField("Название", text: $account.name)
                                .font(.system(size: 16))
                                .foregroundStyle(Color(hex: "#f0f0f5"))
                        }
                        .padding(14)
                        .darkCard()

                        VStack(spacing: 8) {
                            Text("НАЧАЛЬНЫЙ БАЛАНС")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .tracking(1)
                            TextField("0", value: $account.balance, format: .number)
                                .keyboardType(.numberPad)
                                .font(.custom("BebasNeue-Regular", size: 42))
                                .foregroundStyle(Color(hex: "#f0f0f5"))
                                .multilineTextAlignment(.center)
                        }
                        .padding(16)
                        .darkCard()

                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("Удалить счёт")
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .darkCard()
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
            .navigationTitle(account.name.uppercased())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { try? context.save(); dismiss() }
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                }
            }
            .alert("Удалить счёт?", isPresented: $showDeleteConfirm) {
                Button("Удалить", role: .destructive) {
                    context.delete(account)
                    try? context.save()
                    dismiss()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Транзакции привязанные к этому счёту останутся, но потеряют привязку.")
            }
        }
        .preferredColorScheme(.dark)
    }
}
