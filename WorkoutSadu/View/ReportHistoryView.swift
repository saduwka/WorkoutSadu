import SwiftUI
import SwiftData

/// Триггер показа отчёта после выбора периода (день или диапазон).
private struct PendingReport: Identifiable {
    let id = UUID()
    let from: Date
    let to: Date
    var isDay: Bool { Calendar.current.isDate(from, inSameDayAs: to) }
}

/// Список сохранённых отчётов — «что говорил Life Bro» в прошлом.
struct ReportHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedReport.createdAt, order: .reverse) private var reports: [SavedReport]
    @State private var selectedReport: SavedReport?
    @State private var showWeekReport = false
    @State private var showMonthReport = false
    @State private var showCreateReportSheet = false
    @State private var pendingReport: PendingReport?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                if reports.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                        Text("Нет сохранённых отчётов")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(hex: "#f0f0f5"))
                        Text("Итоги дня сохраняются после комментария Life Bro")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        HStack(spacing: 10) {
                            Button { showWeekReport = true } label: {
                                Label("Неделя", systemImage: "calendar")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color(hex: "#ff5c3a"))
                            }
                            .buttonStyle(.plain)
                            Button { showMonthReport = true } label: {
                                Label("Месяц", systemImage: "calendar.badge.clock")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color(hex: "#ff5c3a"))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            HStack(spacing: 10) {
                                Button {
                                    showWeekReport = true
                                } label: {
                                    Label("Итоги недели", systemImage: "calendar")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color(hex: "#ff5c3a"))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color(hex: "#1a1a24"))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                Button {
                                    showMonthReport = true
                                } label: {
                                    Label("Итоги месяца", systemImage: "calendar.badge.clock")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color(hex: "#ff5c3a"))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color(hex: "#1a1a24"))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                            ForEach(reports) { report in
                                Button {
                                    selectedReport = report
                                } label: {
                                    reportRow(report)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("История отчётов")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateReportSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                    }
                }
            }
            .sheet(item: $selectedReport) { report in
                SavedReportDetailView(report: report)
            }
            .sheet(isPresented: $showWeekReport) {
                WeekReportView(dateInWeek: Date())
            }
            .sheet(isPresented: $showMonthReport) {
                MonthReportView(dateInMonth: Date())
            }
            .sheet(isPresented: $showCreateReportSheet) {
                CreateReportSheet { from, to in
                    pendingReport = PendingReport(from: from, to: to)
                }
            }
            .sheet(item: $pendingReport, onDismiss: { pendingReport = nil }) { pr in
                if pr.isDay {
                    DayReportView(date: pr.from)
                } else {
                    RangeReportView(from: pr.from, to: pr.to)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func reportRow(_ report: SavedReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(report.reportType.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "#ff5c3a"))
                    .tracking(1)
                Spacer()
                Text(dateString(report.date))
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#6b6b80"))
            }
            if !report.aiText.isEmpty {
                Text(report.aiText)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
                    .lineLimit(3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#1a1a24"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: date)
    }
}

// MARK: - Detail

private struct SavedReportDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let report: SavedReport

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(report.aiText)
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: "#f0f0f5"))
                        if !report.snapshotData.isEmpty {
                            Text("Сводка")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .tracking(1)
                            Text(report.snapshotData)
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }
            .navigationTitle(report.reportType.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
