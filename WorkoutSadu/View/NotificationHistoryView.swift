import SwiftUI
import SwiftData

/// Элемент для открытия отчёта из истории уведомлений (Identifiable для .fullScreenCover(item:)).
private struct ReportOpenItem: Identifiable {
    let type: String
    let date: Date
    var id: String { "\(type)_\(date.timeIntervalSince1970)" }
}

/// Экран «История уведомлений» — все уведомления из приложения (отчёты дня/недели/месяца, Life Bro, питание и т.д.).
/// По тапу на уведомление отчёта открывается полноценный отчёт для пересмотра.
struct NotificationHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \NotificationEntry.date, order: .reverse) private var entries: [NotificationEntry]
    @State private var reportToOpen: (type: String, date: Date)?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                if entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                        Text("Нет уведомлений")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(hex: "#f0f0f5"))
                        Text("Здесь появятся отчёты дня/недели/месяца, напоминания Life Bro (перекус, вода, комментарии к подходам) и другие уведомления из приложения")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(entries) { entry in
                                notificationRow(entry)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("УВЕДОМЛЕНИЯ")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: reportBinding) { pair in
                ReportFromNotificationContainerView(reportType: pair.type, reportDate: pair.date)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var reportBinding: Binding<ReportOpenItem?> {
        Binding(
            get: {
                guard let t = reportToOpen?.type, let d = reportToOpen?.date else { return nil }
                return ReportOpenItem(type: t, date: d)
            },
            set: { reportToOpen = $0.map { ($0.type, $0.date) } }
        )
    }

    private func notificationRow(_ entry: NotificationEntry) -> some View {
        let isReport = entry.typeRaw == "dayReport" || entry.typeRaw == "weekReport" || entry.typeRaw == "monthReport"
        return Button {
            if isReport {
                reportToOpen = (entry.typeRaw, reportDate(for: entry))
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconForType(entry.typeRaw))
                    .font(.system(size: 18))
                    .foregroundStyle(colorForType(entry.typeRaw))
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    Text(entry.body)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#a0a0b0"))
                        .lineLimit(3)
                    Text(entry.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                Spacer(minLength: 0)
                if isReport {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
            .padding(14)
            .background(Color(hex: "#1a1a24"))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// Дата отчёта по типу уведомления и дате получения (когда пришло уведомление).
    private func reportDate(for entry: NotificationEntry) -> Date {
        let cal = Calendar.current
        switch entry.typeRaw {
        case "dayReport":
            return cal.startOfDay(for: entry.date)
        case "weekReport":
            return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.date)) ?? entry.date
        case "monthReport":
            let prevMonth = cal.date(byAdding: .month, value: -1, to: entry.date) ?? entry.date
            return cal.date(from: cal.dateComponents([.year, .month], from: prevMonth)) ?? entry.date
        default:
            return entry.date
        }
    }

    private func iconForType(_ typeRaw: String) -> String {
        switch typeRaw {
        case "nutritionSnack": return "leaf.fill"
        case "nutritionWater": return "drop.fill"
        case "gymBroComment": return "bubble.left.fill"
        case "dayReport", "weekReport", "monthReport": return "doc.text.fill"
        default: return "bell.fill"
        }
    }

    private func colorForType(_ typeRaw: String) -> Color {
        switch typeRaw {
        case "nutritionSnack": return Color(hex: "#3aff9e")
        case "nutritionWater": return Color(hex: "#5b8cff")
        case "gymBroComment": return Color(hex: "#ff5c3a")
        case "dayReport", "weekReport", "monthReport": return Color(hex: "#ffb830")
        default: return Color(hex: "#6b6b80")
        }
    }
}
