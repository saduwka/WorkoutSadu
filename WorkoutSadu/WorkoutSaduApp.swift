import SwiftUI
import SwiftData
import UserNotifications
import FirebaseCore
import WidgetKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

extension Notification.Name {
    static let openGymBroChat = Notification.Name("openLifeBroChat")
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    static var pendingGymBroOpen = false

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if userInfo["type"] as? String == "gymBroComment" {
            Self.pendingGymBroOpen = true
            NotificationCenter.default.post(name: .openGymBroChat, object: nil)
        }
        completionHandler()
    }
}

struct WidgetSyncModifier: ViewModifier {
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .task {
                WidgetDataManager.sync(context: context)
                WidgetCenter.shared.reloadAllTimelines()
                await FirebaseBackupService.shared.tryExportIfNeeded(context: context)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                WidgetDataManager.sync(context: context)
                WidgetCenter.shared.reloadAllTimelines()
                Task { @MainActor in
                    await FirebaseBackupService.shared.tryExportIfNeeded(context: context)
                }
            }
    }
}

@main
struct WorkoutApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var selectedTab = 0
    @State private var gymBroManager = GymBroManager()

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
                    TodayView()
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
        }
        .modelContainer(for: [
            Workout.self, WorkoutExercise.self, Exercise.self,
            WorkoutSet.self, BodyProfile.self, WorkoutTemplate.self,
            TemplateExercise.self, WeightEntry.self, GymBroChat.self,
            PersistedMessage.self, GeneratedQuest.self, MealEntry.self,
            FinanceTransaction.self, FinanceAccount.self,
            Habit.self, HabitEntry.self, TodoItem.self, WeeklyGoal.self
        ])
    }
}
