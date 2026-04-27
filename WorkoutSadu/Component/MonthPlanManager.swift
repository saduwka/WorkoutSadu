import Foundation
import SwiftData
import FirebaseAI
import Observation

@Observable
final class MonthPlanManager {
    var isGenerating: Bool = false
    var progressMessage: String = ""
    var errorMessage: String?
    var activePlan: MonthPlan?
    
    private let ai = FirebaseAI.firebaseAI(backend: .googleAI())
    
    func loadActive(context: ModelContext) {
        let descriptor = FetchDescriptor<MonthPlan>(
            predicate: #Predicate { $0.isActive == true },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        do {
            activePlan = try context.fetch(descriptor).first
        } catch {
            print("❌ Ошибка загрузки активного плана: \(error)")
            errorMessage = "Ошибка загрузки: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    func generate(workouts: [Workout], profile: BodyProfile?, context: ModelContext) async {
        isGenerating = true
        errorMessage = nil
        
        do {
            progressMessage = "Анализирую тренировки..."
            let lastMonth = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
            let history = workouts.filter { $0.finishedAt != nil && $0.date >= lastMonth }
            
            let analysisText = buildAnalysisText(history: history, profile: profile)
            
            progressMessage = "Строю программу..."
            let model = ai.generativeModel(
                modelName: "gemini-2.5-flash-lite",
                generationConfig: GenerationConfig(responseMIMEType: "application/json")
            )
            
            let prompt = """
            Ты персональный тренер. Проанализируй последние 30 дней тренировок и составь программу на следующие 4 недели.

            ТРЕНИРОВОЧНАЯ ИСТОРИЯ (последние 30 дней):
            \(analysisText)

            ТРЕБОВАНИЯ К ПРОГРАММЕ:
            - СТРОГО 3 тренировки в неделю (например Пн/Ср/Пт или Вт/Чт/Сб — выбери оптимальное)
            - 4 дня отдыха в неделю
            - Прогрессия нагрузки: неделя 1 базовая → неделя 2 +10% объём → неделя 3 пик → неделя 4 -20% дезагрузка
            - Устрани дисбаланс: если какая-то группа < 15% от общего объёма — добавь акцент
            - Для стагнирующих упражнений: смени вариацию или схему подходов
            - Веса указывай реалистично (на основе истории или 0 если нет данных)
            - В summary: 2-3 предложения анализа — что делал хорошо, что исправляем

            ФОРМАТ ОТВЕТА — только JSON, без markdown:
            {
              "summary": "текст анализа 2-3 предложения",
              "weeks": [
                {
                  "week": 1,
                  "focus": "название фокуса недели",
                  "days": [
                    {
                      "day": 1,
                      "name": "Название дня или Отдых",
                      "isRest": false,
                      "exercises": [
                        {"name": "Жим штанги лёжа", "bodyPart": "Грудь", "sets": 4, "reps": 8, "weight": 80.0}
                      ]
                    }
                  ]
                }
              ]
            }
            Возвращай СТРОГО 7 дней в каждой неделе (day 1-7), ровно 3 дня с isRest: false, остальные 4 — isRest: true с пустым exercises: [].
            """
            
            let response = try await model.generateContent(prompt)
            guard var responseText = response.text else {
                throw NSError(domain: "AIError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Пустой ответ от AI"])
            }
            
            print("--- RAW AI RESPONSE ---")
            print(responseText)
            print("-----------------------")
            
            // Очистка от markdown fences
            if let start = responseText.firstIndex(of: "{"),
               let end = responseText.lastIndex(of: "}") {
                responseText = String(responseText[start...end])
            } else {
                // Если не нашли скобки, попробуем просто почистить от ```json
                responseText = responseText
                    .replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            print("--- CLEANED JSON ---")
            print(responseText)
            print("--------------------")
            
            guard let data = responseText.data(using: .utf8) else {
                throw NSError(domain: "AIError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Ошибка конвертации текста в Data"])
            }
            
            progressMessage = "Сохраняю план..."
            do {
                let json = try JSONDecoder().decode(PlanResponse.self, from: data)
                
                let oldPlans = try? context.fetch(FetchDescriptor<MonthPlan>())
                oldPlans?.forEach { $0.isActive = false }
                
                let newPlan = MonthPlan(aiSummary: json.summary)
                context.insert(newPlan)
                
                for weekData in json.weeks {
                    let week = PlanWeek(weekNumber: weekData.week, focus: weekData.focus)
                    week.plan = newPlan
                    context.insert(week)
                    
                    for dayData in weekData.days {
                        let day = PlanDay(dayOfWeek: dayData.day, isRestDay: dayData.isRest, name: dayData.name)
                        day.week = week
                        context.insert(day)
                        
                        if let exs = dayData.exercises {
                            for (idx, exData) in exs.enumerated() {
                                let ex = PlanExercise(order: idx, name: exData.name, bodyPart: exData.bodyPart, sets: exData.sets, reps: exData.reps, weight: exData.weight)
                                ex.day = day
                                context.insert(ex)
                            }
                        }
                    }
                }
                
                try context.save()
                self.activePlan = newPlan
                print("✅ План успешно сгенерирован и сохранен")
                
            } catch {
                print("❌ Ошибка декодирования JSON: \(error)")
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        print("Ключ '\(key.stringValue)' не найден: \(context.debugDescription)")
                    case .valueNotFound(let type, let context):
                        print("Значение типа '\(type)' не найдено: \(context.debugDescription)")
                    case .typeMismatch(let type, let context):
                        print("Несоответствие типа '\(type)': \(context.debugDescription)")
                    case .dataCorrupted(let context):
                        print("Данные повреждены: \(context.debugDescription)")
                    @unknown default:
                        print("Неизвестная ошибка декодирования")
                    }
                }
                throw error
            }
            
        } catch {
            print("❌ Общая ошибка генерации: \(error.localizedDescription)")
            errorMessage = "Ошибка: \(error.localizedDescription)"
        }
        
        isGenerating = false
    }
    
    func startWorkoutFromDay(_ day: PlanDay, context: ModelContext) -> Workout {
        let workout = Workout(name: day.name, date: .now)
        workout.startedAt = .now
        
        for pe in day.exercises.sorted(by: { $0.order < $1.order }) {
            let ex = Exercise(name: pe.name, bodyPart: pe.bodyPart)
            context.insert(ex)
            
            let we = WorkoutExercise(exercise: ex, order: pe.order)
            we.workout = workout
            
            for i in 0..<pe.sets {
                let s = WorkoutSet(order: i, reps: pe.reps, weight: pe.weight)
                we.workoutSets.append(s)
            }
            workout.workoutExercises.append(we)
        }
        
        day.isCompleted = true
        context.insert(workout)
        return workout
    }
    
    private func buildAnalysisText(history: [Workout], profile: BodyProfile?) -> String {
        var text = "Частота: \(history.count) тренировок за месяц.\n"
        if let profile = profile {
            text += "Профиль: Вес \(profile.weight)кг, Цель: \(profile.goal?.title ?? "Не указана")\n"
        }
        
        var volumeByPart: [String: Double] = [:]
        var exerciseHistory: [String: [Double]] = [:]
        
        for w in history {
            for we in w.workoutExercises {
                let part = we.exercise.bodyPart
                let vol = we.workoutSets.reduce(0.0) { $0 + Double($1.reps) * $1.weight }
                volumeByPart[part, default: 0] += vol
                
                let lastWeight = we.workoutSets.last?.weight ?? 0
                exerciseHistory[we.exercise.name, default: []].append(lastWeight)
            }
        }
        
        let totalVolume = volumeByPart.values.reduce(0, +)
        text += "Объём по группам:\n"
        for (part, vol) in volumeByPart {
            let pct = totalVolume > 0 ? (vol / totalVolume * 100) : 0
            text += "- \(part): \(Int(pct))%\n"
        }
        
        let stagnant = exerciseHistory.filter { $0.value.count >= 3 && Set($0.value.suffix(3)).count == 1 }
        if !stagnant.isEmpty {
            text += "Стагнация: \(stagnant.keys.joined(separator: ", "))\n"
        }
        
        return text
    }
}

struct PlanResponse: Codable {
    let summary: String
    let weeks: [WeekJSON]
}

struct WeekJSON: Codable {
    let week: Int
    let focus: String
    let days: [DayJSON]
}

struct DayJSON: Codable {
    let day: Int
    let name: String
    let isRest: Bool
    let exercises: [ExerciseJSON]?
}

struct ExerciseJSON: Codable {
    let name: String
    let bodyPart: String
    let sets: Int
    let reps: Int
    let weight: Double
    
    enum CodingKeys: String, CodingKey {
        case name, bodyPart, sets, reps, weight
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        bodyPart = try container.decode(String.self, forKey: .bodyPart)
        
        // Гибкое декодирование Int/Double для sets и reps
        if let val = try? container.decode(Int.self, forKey: .sets) {
            sets = val
        } else if let val = try? container.decode(Double.self, forKey: .sets) {
            sets = Int(val)
        } else {
            sets = 0
        }
        
        if let val = try? container.decode(Int.self, forKey: .reps) {
            reps = val
        } else if let val = try? container.decode(Double.self, forKey: .reps) {
            reps = Int(val)
        } else {
            reps = 0
        }
        
        // Гибкое декодирование weight (Int или Double)
        if let val = try? container.decode(Double.self, forKey: .weight) {
            weight = val
        } else if let val = try? container.decode(Int.self, forKey: .weight) {
            weight = Double(val)
        } else {
            weight = 0.0
        }
    }
}
