import SwiftUI
import SwiftData

/// Дневной отчёт: карточки сводки + AI-комментарий Life Bro (стриминг).
struct DayReportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let date: Date
    /// При открытии из уведомления — сразу запросить комментарий Life Bro.
    var autoRequestComment: Bool = false

    @State private var snapshot: DayReportSnapshot?
    @State private var aiComment: String = ""
    @State private var isStreaming = false
    @State private var streamError: String?
    @State private var hasRequestedComment = false
    @State private var showMoodSheet = false

    init(date: Date = Date(), autoRequestComment: Bool = false) {
        self.date = date
        self.autoRequestComment = autoRequestComment
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        if let s = snapshot {
                            reportCards(snapshot: s)
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
            .navigationTitle("Итоги дня")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
            .onAppear {
                if snapshot == nil {
                    snapshot = ReportManager.shared.collectDaySnapshot(context: context, date: date)
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
    private func reportCards(snapshot s: DayReportSnapshot) -> some View {
        if !s.workoutSummary.isEmpty {
            reportCard(title: "Тренировка", icon: "flame.fill", color: Color(hex: "#ff5c3a")) {
                Text(s.workoutSummary)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
            }
        }

        reportCard(title: "Калории", icon: "fork.knife", color: Color(hex: "#3aff9e")) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Съедено: \(s.caloriesEaten) ккал")
                Text("Сожжено: \(s.caloriesBurned) ккал")
                if let t = s.calorieTarget {
                    Text("Норма: \(t) ккал")
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(Color(hex: "#f0f0f5"))
        }

        if !s.mealsDetail.isEmpty {
            reportCard(title: "Еда", icon: "fork.knife.circle", color: Color(hex: "#3aff9e")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(s.mealsDetail.enumerated()), id: \.offset) { _, m in
                        HStack(alignment: .top, spacing: 8) {
                            Text(m.timeString)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .frame(width: 40, alignment: .leading)
                            Text(m.mealType)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(hex: "#3aff9e").opacity(0.9))
                            Text(m.name)
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "#f0f0f5"))
                            Spacer()
                            Text("\(m.calories) ккал")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                        }
                    }
                }
            }
        }

        if s.waterML > 0 {
            reportCard(title: "Вода", icon: "drop.fill", color: Color(hex: "#5b8cff")) {
                Text("\(s.waterML) мл")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
            }
        }

        if s.expense > 0 || s.income > 0 {
            reportCard(title: "Деньги", icon: "banknote.fill", color: Color(hex: "#5b8cff")) {
                HStack(spacing: 16) {
                    Text("Расход: −\(formatAmount(s.expense))")
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                    Text("Доход: +\(formatAmount(s.income))")
                        .foregroundStyle(Color(hex: "#3aff9e"))
                }
                .font(.system(size: 14))
            }
        }

        if s.habitsTotal > 0 {
            reportCard(title: "Привычки", icon: "repeat", color: Color(hex: "#ffb830")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(s.habitsDone)/\(s.habitsTotal)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    ForEach(Array(s.habitsList.enumerated()), id: \.offset) { _, h in
                        HStack(spacing: 6) {
                            Image(systemName: h.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(h.done ? Color(hex: "#3aff9e") : Color(hex: "#6b6b80"))
                            Text(h.name)
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#f0f0f5"))
                            if h.streak > 0 {
                                Text("\(h.streak) дн.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(hex: "#ffb830"))
                            }
                        }
                    }
                }
            }
        }

        if s.todosDone > 0 || s.todosPending > 0 {
            reportCard(title: "Задачи", icon: "checklist", color: Color(hex: "#a855f7")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Выполнено: \(s.todosDone), в ожидании: \(s.todosPending)")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    if !s.todoTitles.isEmpty {
                        Text(s.todoTitles.prefix(5).joined(separator: ", "))
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                    }
                }
            }
        }

        reportCard(title: "Настроение", icon: "face.smiling", color: Color(hex: "#f472b6")) {
            if let r = s.moodRating {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(r)/5")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    if !s.moodNote.isEmpty {
                        Text(s.moodNote)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                    }
                }
            }
            Button {
                showMoodSheet = true
            } label: {
                Text(s.moodRating == nil ? "Оценить день" : "Изменить")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: "#f472b6"))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showMoodSheet) {
            MoodEntrySheet(date: date) {
                snapshot = ReportManager.shared.collectDaySnapshot(context: context, date: date)
            }
        }

        if !s.goalsList.isEmpty {
            reportCard(title: "Цели", icon: "target", color: Color(hex: "#ffb830")) {
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
    private func lifeBroSection(snapshot s: DayReportSnapshot) -> some View {
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

    private func requestComment(snapshot s: DayReportSnapshot) {
        hasRequestedComment = true
        isStreaming = true
        streamError = nil
        aiComment = ""
        let prompt = ReportManager.shared.buildDayReportPrompt(snapshot: s, date: date)

        Task {
            do {
                for try await chunk in ReportManager.shared.generateReportCommentStream(prompt: prompt) {
                    await MainActor.run { aiComment += chunk }
                }
                await MainActor.run {
                    isStreaming = false
                    saveReportIfNeeded(aiText: aiComment, snapshot: s)
                }
            } catch {
                await MainActor.run {
                    isStreaming = false
                    streamError = error.localizedDescription
                }
            }
        }
    }

    private func saveReportIfNeeded(aiText: String, snapshot: DayReportSnapshot) {
        let report = SavedReport(type: .day, date: date, aiText: aiText, snapshotData: snapshot.textSummary)
        context.insert(report)
        try? context.save()
    }

    private func formatAmount(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        let absStr = f.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        return value < 0 ? "−\(absStr)" : absStr
    }
}

// MARK: - Mood Entry Sheet

private struct MoodEntrySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let onSaved: () -> Void

    @State private var rating: Int = 3
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                VStack(spacing: 20) {
                    Text("Как настроение?")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { n in
                            Button {
                                rating = n
                            } label: {
                                Text("\(n)")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(rating == n ? .white : Color(hex: "#6b6b80"))
                                    .frame(width: 44, height: 44)
                                    .background(rating == n ? Color(hex: "#f472b6") : Color(hex: "#1a1a24"))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    TextField("Заметка (необязательно)", text: $note)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                        .padding(12)
                        .background(Color(hex: "#1a1a24"))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(24)
            }
            .navigationTitle("Настроение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        saveMood()
                        onSaved()
                        dismiss()
                    }
                    .foregroundStyle(Color(hex: "#ff5c3a"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func saveMood() {
        let cal = Calendar.current
        let descriptor = FetchDescriptor<MoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let existing = try? context.fetch(descriptor).first(where: { cal.isDate($0.date, inSameDayAs: date) }) {
            existing.rating = min(5, max(1, rating))
            existing.note = note
        } else {
            let entry = MoodEntry(rating: rating, note: note, date: date)
            context.insert(entry)
        }
        try? context.save()
    }
}
