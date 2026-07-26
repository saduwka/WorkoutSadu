import SwiftUI
import SwiftData
import UserNotifications
import FirebaseCore
import WidgetKit
import CoreFoundation
import BackgroundTasks

private let receiptSavedDarwinName = "com.saduwka.WorkoutSadu.receiptSaved"

private func receiptSavedDarwinCallback(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    // Reload UI if needed
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        print("🚀 AppDelegate: didFinishLaunching start")
        FirebaseApp.configure()
        print("🔥 Firebase configured")
        HomeBackupService.registerBGTask()
        HomeBackupService.scheduleNextBGTask()
        ReportManager.shared.scheduleAllReportNotifications()
        NutritionReminderService.scheduleRecurringReminders()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            receiptSavedDarwinCallback,
            receiptSavedDarwinName as CFString,
            nil,
            .deliverImmediately
        )
        print("🚀 AppDelegate: didFinishLaunching end")
        return true
    }
}

extension Notification.Name {
    static let openGymBroChat = Notification.Name("openLifeBroChat")
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    static var pendingGymBroOpen = false
    static var pendingNutritionOpen = false
    static var pendingHomeBackupOpen = false
    /// По тапу на отчёт: открыть полноценный отчёт (день/неделя/месяц).
    static var pendingReportType: String?
    static var pendingReportDate: Date?
    /// Контекст для сохранения уведомлений в историю (ставится из WidgetSyncModifier).
    var modelContext: ModelContext?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        saveNotificationToHistory(content: notification.request.content)
        if notification.request.identifier == "rest-timer-done" {
            completionHandler([.banner])
        } else {
            completionHandler([.banner, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let request = response.notification.request
        if request.identifier == TimerManager.notificationID
            || request.content.categoryIdentifier == TimerManager.notificationCategoryID {
            let action = response.actionIdentifier
            // Стоп по кнопке / свайпу. Тап по телу уведомления тоже глушит,
            // но система может открыть приложение — для «не открывать» жми «Отключить».
            if action == TimerManager.dismissActionID
                || action == UNNotificationDefaultActionIdentifier
                || action == UNNotificationDismissActionIdentifier {
                DispatchQueue.main.async {
                    TimerManager.shared.stop()
                }
            }
            completionHandler()
            return
        }

        let userInfo = request.content.userInfo
        let type = userInfo["type"] as? String
        if type == "gymBroComment" {
            Self.pendingGymBroOpen = true
            NotificationCenter.default.post(name: .openGymBroChat, object: nil)
        } else if type == "nutritionPrompt" || type == "nutritionWater" || type == "nutritionSnack" {
            Self.pendingNutritionOpen = true
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
        } else if type == "homeBackupFailed" {
            Self.pendingHomeBackupOpen = true
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

struct FirebaseSyncModifier: ViewModifier {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [BodyProfile]

    func body(content: Content) -> some View {
        content
            .onAppear {
                NotificationDelegate.shared.modelContext = context
                WatchConnectivityManager.shared.configure(context: context)
                WatchConnectivityManager.shared.updateProfiles(profiles)
                WatchConnectivityManager.shared.republishActiveWorkout()
            }
            .onChange(of: profiles.count) { _, _ in
                WatchConnectivityManager.shared.updateProfiles(profiles)
            }
            .task {
                await FirebaseBackupService.shared.tryExportIfNeeded(context: context)
                await HomeBackupService.shared.tryHomeExportIfNeeded(context: context)
                HomeBackupService.scheduleNextBGTask()
                NutritionReminderService.checkAndSchedule(context: context)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                NutritionReminderService.checkAndSchedule(context: context)
                Task { @MainActor in
                    await FirebaseBackupService.shared.tryExportIfNeeded(context: context)
                    await HomeBackupService.shared.tryHomeExportIfNeeded(context: context)
                    HomeBackupService.scheduleNextBGTask()
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

private func registerRestTimerNotificationCategory() {
    // Без .foreground — «Отключить» глушит таймер в фоне и не открывает приложение
    // (как стоп у системного таймера на часах, чтобы не выкидывать из «Тренировка»).
    let dismiss = UNNotificationAction(
        identifier: TimerManager.dismissActionID,
        title: "Отключить",
        options: []
    )
    let category = UNNotificationCategory(
        identifier: TimerManager.notificationCategoryID,
        actions: [dismiss],
        intentIdentifiers: [],
        options: [.customDismissAction]
    )
    UNUserNotificationCenter.current().setNotificationCategories([category])
}

@main
struct WorkoutApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var selectedTab = 0
    @State private var tasksSection = 0
    @State private var gymBroManager = GymBroManager()
    @State private var showReportFromNotification = false
    @State private var reportFromNotificationType: String?
    @State private var reportFromNotificationDate: Date?
    @AppStorage("userDisplayName") private var userDisplayName = ""
    @State private var showLaunchWelcome = true

    init() {
        print("📱 WorkoutApp: init start")
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        registerRestTimerNotificationCategory()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        print("🔔 Notifications authorized")

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
                    TodayView(selectedTab: $selectedTab, tasksSection: $tasksSection)
                        .tabItem { Label("Сегодня", systemImage: "sun.max.fill") }
                        .tag(0)

                    HealthTabView()
                        .tabItem { Label("Здоровье", systemImage: "heart.fill") }
                        .tag(1)

                    TasksTabView(section: $tasksSection)
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

                if showLaunchWelcome {
                    LaunchWelcomeView(userName: userDisplayName)
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(.easeInOut(duration: 0.45)) {
                    showLaunchWelcome = false
                }
            }
            .onAppear {
                print("✅ App successfully launched and appeared")
            }
            .environment(gymBroManager)
            .modifier(FirebaseSyncModifier())
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                if let t = NotificationDelegate.pendingReportType, let d = NotificationDelegate.pendingReportDate {
                    reportFromNotificationType = t
                    reportFromNotificationDate = d
                    selectedTab = 4
                    showReportFromNotification = true
                } else if NotificationDelegate.pendingNutritionOpen {
                    NotificationDelegate.pendingNutritionOpen = false
                    selectedTab = 1
                } else if NotificationDelegate.pendingHomeBackupOpen {
                    NotificationDelegate.pendingHomeBackupOpen = false
                    selectedTab = 4
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
            WaterEntry.self, NotificationEntry.self,
            MonthPlan.self, PlanWeek.self, PlanDay.self, PlanExercise.self
        ])
    }
}
  
