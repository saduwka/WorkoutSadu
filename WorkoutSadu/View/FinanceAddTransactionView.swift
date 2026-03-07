import SwiftUI
import SwiftData

struct FinanceAddTransactionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FinanceAccount.createdAt) private var accounts: [FinanceAccount]

    @State private var name = ""
    @State private var amountText = ""
    @State private var selectedCategory: FinanceCategory = .other
    @State private var selectedType: FinanceType = .expense
    @State private var selectedAccountID: UUID?
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        typeSelector
                        amountCard
                        if !accounts.isEmpty {
                            accountPicker
                            if selectedAccountID == nil {
                                Text("Выберите счёт для сохранения")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(hex: "#ff5c3a"))
                            }
                        } else {
                            Text("Создайте счёт в разделе «Финансы», чтобы добавлять транзакции")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 8)
                        }
                        detailsCard
                        categoryCard
                        saveButton
                    }
                    .dismissKeyboardOnTap()
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("НОВАЯ ЗАПИСЬ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Type

    private var typeSelector: some View {
        Picker("", selection: $selectedType) {
            ForEach(FinanceType.allCases, id: \.self) { t in
                Text(t.rawValue).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedType) {
            if selectedType == .income { selectedCategory = .income }
            else if selectedCategory == .income { selectedCategory = .other }
        }
    }

    // MARK: - Amount

    private var amountCard: some View {
        VStack(spacing: 8) {
            Text("СУММА")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)
            TextField("0", text: $amountText)
                .keyboardType(.numberPad)
                .font(.custom("BebasNeue-Regular", size: 48))
                .foregroundStyle(selectedType == .income ? Color(hex: "#3aff9e") : Color(hex: "#f0f0f5"))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .darkCard()
    }

    // MARK: - Account picker

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
                        Button { selectedAccountID = acc.id } label: {
                            HStack(spacing: 6) {
                                Image(systemName: acc.icon)
                                    .font(.system(size: 12))
                                Text(acc.name)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(selectedAccountID == acc.id ? .white : Color(hex: "#6b6b80"))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(selectedAccountID == acc.id ? Color(hex: acc.colorHex) : Color(hex: "#1a1a24"))
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

    // MARK: - Details

    private var detailsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "pencil").foregroundStyle(Color(hex: "#6b6b80"))
                TextField("Название", text: $name)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
            }
            .padding(14)
            .background(Color(hex: "#1a1a24"))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            DatePicker("Дата", selection: $date, displayedComponents: .date)
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: "#f0f0f5"))
                .tint(Color(hex: "#ff5c3a"))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(hex: "#1a1a24"))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .darkCard()
    }

    // MARK: - Category

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("КАТЕГОРИЯ")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)
                .padding(.horizontal, 4)

            let categories = selectedType == .income
                ? [FinanceCategory.income]
                : FinanceCategory.allCases.filter { $0 != .income }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    Button {
                        selectedCategory = cat
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(selectedCategory == cat ? Color(hex: cat.color) : Color(hex: "#6b6b80"))
                            Text(cat.rawValue)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(selectedCategory == cat ? Color(hex: "#f0f0f5") : Color(hex: "#6b6b80"))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedCategory == cat ? Color(hex: cat.color).opacity(0.15) : Color(hex: "#1a1a24"))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedCategory == cat ? Color(hex: cat.color).opacity(0.4) : .clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .darkCard()
    }

    // MARK: - Save

    private var canSave: Bool {
        guard let amount = Int(amountText), amount > 0 else { return false }
        guard !accounts.isEmpty else { return false }
        return selectedAccountID != nil
    }

    private var saveButton: some View {
        Button {
            guard canSave, let accountID = selectedAccountID else { return }
            let amount = Int(amountText) ?? 0
            let tx = FinanceTransaction(
                name: name.isEmpty ? selectedCategory.rawValue : name,
                amount: amount,
                category: selectedCategory,
                type: selectedType,
                date: date,
                accountID: accountID
            )
            context.insert(tx)
            try? context.save()
            dismiss()
        } label: {
            Text("Сохранить")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    canSave
                        ? Color(hex: "#ff5c3a")
                        : Color(hex: "#6b6b80").opacity(0.4)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!canSave)
    }
}
