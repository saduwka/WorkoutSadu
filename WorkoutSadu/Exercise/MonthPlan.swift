import Foundation
import SwiftData

@Model
final class MonthPlan {
    var id: UUID = UUID()
    var generatedAt: Date = Date()
    var periodStart: Date = Date() // Начало следующих 30 дней
    var aiSummary: String = ""
    var isActive: Bool = true
    
    @Relationship(deleteRule: .cascade, inverse: \PlanWeek.plan)
    var weeks: [PlanWeek] = []
    
    init(generatedAt: Date = .now, periodStart: Date = .now, aiSummary: String = "") {
        self.id = UUID()
        self.generatedAt = generatedAt
        self.periodStart = periodStart
        self.aiSummary = aiSummary
        self.isActive = true
    }
}

@Model
final class PlanWeek {
    var id: UUID = UUID()
    var weekNumber: Int = 1
    var focus: String = ""
    var plan: MonthPlan?
    
    @Relationship(deleteRule: .cascade, inverse: \PlanDay.week)
    var days: [PlanDay] = []
    
    init(weekNumber: Int, focus: String) {
        self.id = UUID()
        self.weekNumber = weekNumber
        self.focus = focus
    }
}

@Model
final class PlanDay {
    var id: UUID = UUID()
    var dayOfWeek: Int = 1 // 1=Пн ... 7=Вс
    var isRestDay: Bool = false
    var name: String = ""
    var isCompleted: Bool = false
    var week: PlanWeek?
    
    @Relationship(deleteRule: .cascade, inverse: \PlanExercise.day)
    var exercises: [PlanExercise] = []
    
    init(dayOfWeek: Int, isRestDay: Bool, name: String) {
        self.id = UUID()
        self.dayOfWeek = dayOfWeek
        self.isRestDay = isRestDay
        self.name = name
        self.isCompleted = false
    }
}

@Model
final class PlanExercise {
    var id: UUID = UUID()
    var order: Int = 0
    var name: String = ""
    var bodyPart: String = ""
    var sets: Int = 0
    var reps: Int = 0
    var weight: Double = 0.0
    var day: PlanDay?
    
    init(order: Int, name: String, bodyPart: String, sets: Int, reps: Int, weight: Double) {
        self.id = UUID()
        self.order = order
        self.name = name
        self.bodyPart = bodyPart
        self.sets = sets
        self.reps = reps
        self.weight = weight
    }
}
