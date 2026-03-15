import SwiftUI
import SwiftData

/// Недельный отчёт: карточки сводки + AI-комментарий Life Bro.
struct WeekReportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let dateInWeek: Date
    var autoRequestComment: Bool = false

    @State private var snapshot: WeekReportSnapshot?
    @State private var aiComment: String = ""
    @State private var isStreaming = false
    @State private var streamError: String?
    @State private var hasRequestedComment = false

    init(dateInWeek: Date = Date(), autoRequestComment: Bool = false) {
        self.dateInWeek = dateInWeek
        self.autoRequestComment = autoRequestComment
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        if let s = snapshot {
                            weekCards(snapshot: s)
                            lifeBroSection(snapshot: s)
                        } else {
                            ProgressView()
                                .tint(Color(hex: "#ff5c3a"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Неделя")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
            .onAppear {
                if snapshot == nil {
                    snapshot = ReportManager.shared.collectWeekSnapshot(context: context, dateInWeek: dateInWeek)
                }
            }
            .onChange(of: snapshot) { _, newSnapshot in
                if let s = newSnapshot, autoRequestComment, !hasRequestedComment {
                    requestComment(snapshot: s)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func weekCards(snapshot s: WeekReportSnapshot) -> some View {
        reportCard(title: "Тренировки", icon: "flame.fill", color: Color(hex: "#ff5c3a")) {
            Text("\(s.workoutsCount) за неделю")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "#f0f0f5"))
            if !s.workoutNames.isEmpty {
                Text(s.workoutNames.prefix(5).joined(separator: ", "))
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#6b6b80"))
            }
        }

        if !s.weightEntries.isEmpty {
            let w = s.weightEntries.sorted { $0.date < $1.date }
            if let first = w.first, let last = w.last {
                reportCard(title: "Вес", icon: "scalemass.fill", color: Color(hex: "#5b8cff")) {
                    Text("\(Int(first.weight)) → \(Int(last.weight)) кг")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                }
            }
        }

        reportCard(title: "Деньги", icon: "banknote.fill", color: Color(hex: "#3aff9e")) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Расход: −\(formatAmount(s.totalExpense))")
                    .foregroundStyle(Color(hex: "#ff5c3a"))
                Text("Доход: +\(formatAmount(s.totalIncome))")
                    .foregroundStyle(Color(hex: "#3aff9e"))
            }
            .font(.system(size: 14))
        }

        if !s.topExpensesByCategory.isEmpty {
            reportCard(title: "Топ расходов", icon: "chart.pie.fill", color: Color(hex: "#a855f7")) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(s.topExpensesByCategory.prefix(5).enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.category)
                                .foregroundStyle(Color(hex: "#f0f0f5"))
                            Spacer()
                            Text(formatAmount(item.amount))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                        }
                        .font(.system(size: 13))
                    }
                }
            }
        }

        if !s.habitsKept.isEmpty || !s.habitsBroke.isEmpty {
            reportCard(title: "Привычки", icon: "repeat", color: Color(hex: "#ffb830")) {
                VStack(alignment: .leading, spacing: 4) {
                    if !s.habitsKept.isEmpty {
                        Text("Держали: \(s.habitsKept.map { "\($0.name) (\($0.streak) дн.)" }.joined(separator: ", "))")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#3aff9e"))
                    }
                    if !s.habitsBroke.isEmpty {
                        Text("Сломали: \(s.habitsBroke.joined(separator: ", "))")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                    }
                }
            }
        }

        if !s.goalsList.isEmpty {
            reportCard(title: "Цели недели", icon: "target", color: Color(hex: "#ffb830")) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(s.goalsList.enumerated()), id: \.offset) { _, g in
                        Text("\(g.title): \(g.current)/\(g.target)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#f0f0f5"))
                    }
                }
            }
        }
    }

    private func reportCard<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .tracking(1)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .darkCard()
    }

    @ViewBuilder
    private func lifeBroSection(snapshot s: WeekReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(Color(hex: "#ff5c3a"))
                Text("КОММЕНТАРИЙ LIFE BRO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .tracking(1)
            }
            if isStreaming || !aiComment.isEmpty {
                Text(aiComment.isEmpty ? "…" : aiComment)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let err = streamError {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#ff5c3a"))
            }
            if !hasRequestedComment && !isStreaming {
                Button {
                    requestComment(snapshot: s)
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Получить комментарий")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(hex: "#ff5c3a"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isStreaming)
            }
        }
        .padding(14)
        .darkCard()
    }

    private func requestComment(snapshot s: WeekReportSnapshot) {
        hasRequestedComment = true
        isStreaming = true
        streamError = nil
        aiComment = ""
        let prompt = ReportManager.shared.buildWeekReportPrompt(snapshot: s)
        Task {
            do {
                for try await chunk in ReportManager.shared.generateReportCommentStream(prompt: prompt) {
                    await MainActor.run { aiComment += chunk }
                }
                await MainActor.run {
                    isStreaming = false
                    let report = SavedReport(type: .week, date: s.weekStart, aiText: aiComment, snapshotData: s.textSummary)
                    context.insert(report)
                    try? context.save()
                }
            } catch {
                await MainActor.run {
                    isStreaming = false
                    streamError = error.localizedDescription
                }
            }
        }
    }

    private func formatAmount(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        let absStr = f.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        return value < 0 ? "−\(absStr)" : absStr
    }
}
