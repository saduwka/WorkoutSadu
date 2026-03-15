import SwiftUI
import SwiftData
import UserNotifications
import FirebaseCore
import WidgetKit
import CoreFoundation

private let receiptSavedDarwinName = "com.saduwka.WorkoutSadu.receiptSaved"

private func receiptSavedDarwinCallback(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    DispatchQueue.main.async {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        ReportManager.shared.scheduleAllReportNotifications()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            receiptSavedDarwinCallback,
            receiptSavedDarwinName as CFString,
            nil,
            .deliverImmediately
        )
        return true
    }
}

extension Notification.Name {
    static let openGymBroChat = Notification.Name("openLifeBroChat")
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    static var pendingGymBroOpen = false
    /// По тапу на отчёт: открыть полноценный отчёт (день/неделя/месяц).
    static var pendingReportType: String?
    static var pendingReportDate: Date?
    /// Контекст для сохранения уведомлений в историю (ставится из WidgetSyncModifier).
    var modelContext: ModelContext?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        saveNotificationToHistory(content: notification.request.content)
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let type = userInfo["type"] as? String
        if type == "gymBroComment" {
            Self.pendingGymBroOpen = true
            NotificationCenter.default.post(name: .openGymBroChat, object: nil)
        } else if type == "dayReport" || type == "weekReport" || type == "monthReport" {
            let cal = Calendar.current
            let now = Date()
            switch type {
            case "dayReport":
                Self.pendingReportDate = cal.date(byAdding: .day, value: -1, to: now) ?? now
            case "weekReport":
                let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
                Self.pendingReportDate = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: lastWeek)) ?? lastWeek
            case "monthReport":
                Self.pendingReportDate = cal.date(from: cal.dateComponents([.year, .month], from: cal.date(byAdding: .month, value: -1, to: now)!)) ?? now
            default:
                break
            }
            Self.pendingReportType = type
        }
        saveNotificationToHistory(content: response.notification.request.content)
        completionHandler()
    }

    private func saveNotificationToHistory(content: UNNotificationContent) {
        guard let ctx = modelContext else { return }
        let type = (content.userInfo["type"] as? String) ?? ""
        DispatchQueue.main.async {
            ctx.insert(NotificationEntry(
                title: content.title,
                body: content.body,
                date: Date(),
                typeRaw: type.isEmpty ? "unknown" : type
            ))
            try? ctx.save()
        }
    }
}

struct WidgetSyncModifier: ViewModifier {
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .onAppear {
                NotificationDelegate.shared.modelContext = context
            }
            .task {
                WidgetDataManager.sync(context: context)
                WidgetCenter.shared.reloadAllTimelines()
                await FirebaseBackupService.shared.tryExportIfNeeded(context: context)
                NutritionReminderService.checkAndSchedule(context: context)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                WidgetDataManager.sync(context: context)
                WidgetCenter.shared.reloadAllTimelines()
                NutritionReminderService.checkAndSchedule(context: context)
                Task { @MainActor in
                    await FirebaseBackupService.shared.tryExportIfNeeded(context: context)
                }
            }
    }
}

/// Контейнер для открытия отчёта по тапу на уведомление (день/неделя/месяц).
struct ReportFromNotificationContainerView: View {
    let reportType: String
    let reportDate: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch reportType {
            case "dayReport":
                DayReportView(date: reportDate, autoRequestComment: true)
            case "weekReport":
                WeekReportView(dateInWeek: reportDate, autoRequestComment: true)
            case "monthReport":
                MonthReportView(dateInMonth: reportDate, autoRequestComment: true)
            default:
                EmptyView()
            }
        }
        .onDisappear {
            NotificationDelegate.pendingReportType = nil
            NotificationDelegate.pendingReportDate = nil
        }
    }
}

@main
struct WorkoutApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var selectedTab = 0
    @State private var gymBroManager = GymBroManager()
    @State private var showReportFromNotification = false
    @State private var reportFromNotificationType: String?
    @State private var reportFromNotificationDate: Date?

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(red: 0.055, green: 0.055, blue: 0.071, alpha: 1)
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(red: 0.42, green: 0.42, blue: 0.50, alpha: 1)
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(red: 0.42, green: 0.42, blue: 0.50, alpha: 1)]
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(red: 1, green: 0.36, blue: 0.23, alpha: 1)
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(red: 1, green: 0.36, blue: 0.23, alpha: 1)]
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(red: 0.055, green: 0.055, blue: 0.071, alpha: 1)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1)]
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1),
            .font: UIFont(name: "BebasNeue-Regular", size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    }

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .bottomTrailing) {
                TabView(selection: $selectedTab) {
                    TodayView(selectedTab: $selectedTab)
                        .tabItem { Label("Сегодня", systemImage: "sun.max.fill") }
                        .tag(0)

                    HealthTabView()
                        .tabItem { Label("Здоровье", systemImage: "heart.fill") }
                        .tag(1)

                    TasksTabView()
                        .tabItem { Label("Задачи", systemImage: "checklist") }
                        .tag(2)

                    FinanceView()
                        .tabItem { Label("Деньги", systemImage: "banknote.fill") }
                        .tag(3)

                    MeTabView()
                        .tabItem { Label("Я", systemImage: "person.fill") }
                        .tag(4)
                }
                .preferredColorScheme(.dark)

                GymBroOverlay()
            }
            .environment(gymBroManager)
            .modifier(WidgetSyncModifier())
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                if let t = NotificationDelegate.pendingReportType, let d = NotificationDelegate.pendingReportDate {
                    reportFromNotificationType = t
                    reportFromNotificationDate = d
                    selectedTab = 4
                    showReportFromNotification = true
                } else if PendingReceiptStorage.hasPendingReceiptFile() {
                    selectedTab = 3
                }
            }
            .fullScreenCover(isPresented: $showReportFromNotification) {
                if let t = reportFromNotificationType, let d = reportFromNotificationDate {
                    ReportFromNotificationContainerView(reportType: t, reportDate: d)
                }
            }
            .onChange(of: showReportFromNotification) { _, showing in
                if !showing {
                    reportFromNotificationType = nil
                    reportFromNotificationDate = nil
                }
            }
        }
        .modelContainer(for: [
            Workout.self, WorkoutExercise.self, Exercise.self,
            WorkoutSet.self, BodyProfile.self, WorkoutTemplate.self,
            TemplateExercise.self, WeightEntry.self, GymBroChat.self,
            PersistedMessage.self, GeneratedQuest.self, MealEntry.self,
            FinanceTransaction.self, FinanceAccount.self,
            Habit.self, HabitEntry.self, TodoItem.self, WeeklyGoal.self,
            MoodEntry.self, SavedReport.self,
            WaterEntry.self, NotificationEntry.self
        ])
    }
}
