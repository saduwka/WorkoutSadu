import Foundation
import SwiftData
import UserNotifications

/// Проверяет последний приём пищи и воду за день, при необходимости планирует локальные push от имени Life Bro («перекуси», «попей воды»).
/// Вызывается при возврате в приложение (например, из WidgetSyncModifier).
enum NutritionReminderService {
    static let snackNotificationID = "lifebro.snack"
    static let waterNotificationID = "lifebro.water"

    private static let lastSnackReminderKey = "lifebro.lastSnackReminderDate"
    private static let lastWaterReminderKey = "lifebro.lastWaterReminderDate"

    /// Часы без еды, после которых предлагаем перекусить.
    private static let hoursWithoutFoodThreshold: Double = 4
    /// Ниже этой суммы (мл) за день — напоминаем попить воды.
    private static let waterReminderBelowML = 1000
    /// С какого часа (включительно) напоминаем про воду.
    private static let waterReminderFromHour = 12
    /// Часы дня, когда показываем напоминание про перекус (включительно).
    private static let snackActiveHours = 8...21

    /// Проверить данные и при выполнении условий запланировать уведомления. Вызывать с главного потока, с тем же context, что и UI.
    static func checkAndSchedule(context: ModelContext) {
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let startOfToday = cal.startOfDay(for: now)

        // Последний приём пищи
        var mealDesc = FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        mealDesc.fetchLimit = 1
        let lastMeals = (try? context.fetch(mealDesc)) ?? []
        let lastMealDate = lastMeals.first?.date

        if let last = lastMealDate {
            let hoursSince = now.timeIntervalSince(last) / 3600
            if hoursSince >= Self.hoursWithoutFoodThreshold && Self.snackActiveHours.contains(hour) {
                tryRemindSnack(startOfToday: startOfToday, context: context)
            }
        } else if Self.snackActiveHours.contains(hour) {
            // Нет ни одного приёма пищи — мягко напомнить
            tryRemindSnack(startOfToday: startOfToday, context: context)
        }

        // Вода за сегодня (predicate по дате — не зависим от лимита 200 записей)
        let startOfDay = cal.startOfDay(for: now)
        var waterDesc = FetchDescriptor<WaterEntry>(
            predicate: #Predicate<WaterEntry> { $0.date >= startOfDay },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        waterDesc.fetchLimit = 50
        let waterEntries = (try? context.fetch(waterDesc)) ?? []
        let todayWaterML = waterEntries.reduce(0) { $0 + $1.amountML }

        if todayWaterML < Self.waterReminderBelowML && hour >= Self.waterReminderFromHour {
            tryRemindWater(startOfToday: startOfToday, context: context)
        }
    }

    private static func tryRemindSnack(startOfToday: Date, context: ModelContext) {
        let last = UserDefaults.standard.object(forKey: Self.lastSnackReminderKey) as? Date
        if let last = last, Calendar.current.isDate(last, inSameDayAs: startOfToday) {
            return
        }
        UserDefaults.standard.set(startOfToday, forKey: Self.lastSnackReminderKey)

        let content = UNMutableNotificationContent()
        content.title = "Life Bro"
        content.body = "Пора перекусить? 🍎"
        content.sound = .default
        content.userInfo = ["type": "nutritionSnack"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: Self.snackNotificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
        context.insert(NotificationEntry(title: content.title, body: content.body, typeRaw: "nutritionSnack"))
        try? context.save()
    }

    private static func tryRemindWater(startOfToday: Date, context: ModelContext) {
        let last = UserDefaults.standard.object(forKey: Self.lastWaterReminderKey) as? Date
        if let last = last, Calendar.current.isDate(last, inSameDayAs: startOfToday) {
            return
        }
        UserDefaults.standard.set(startOfToday, forKey: Self.lastWaterReminderKey)

        let content = UNMutableNotificationContent()
        content.title = "Life Bro"
        content.body = "Не забудь попить воды 💧"
        content.sound = .default
        content.userInfo = ["type": "nutritionWater"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: Self.waterNotificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
        context.insert(NotificationEntry(title: content.title, body: content.body, typeRaw: "nutritionWater"))
        try? context.save()
    }
}
