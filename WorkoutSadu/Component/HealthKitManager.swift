import Foundation
import HealthKit
import SwiftData

@MainActor
class HealthKitManager {
    static let shared = HealthKitManager()
    let healthStore = HKHealthStore()

    private init() {}

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HKError(.errorHealthDataUnavailable)
        }

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietaryWater)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
    }

    func saveWorkout(_ workout: Workout, calories: Int) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let start = workout.startedAt ?? workout.date
        let end = workout.finishedAt ?? Date()
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())

        do {
            try await builder.beginCollection(at: start)
            
            let energyBurned = HKQuantity(unit: .kilocalorie(), doubleValue: Double(calories))
            let energySample = HKQuantitySample(type: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
                                              quantity: energyBurned,
                                              start: start,
                                              end: end)
            try await builder.addSamples([energySample])
            
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            print("Error saving workout to HealthKit: \(error.localizedDescription)")
        }
    }

    func saveMeal(_ meal: MealEntry) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        var samples: [HKQuantitySample] = []
        let date = meal.date

        if meal.calories > 0 {
            let energy = HKQuantity(unit: .kilocalorie(), doubleValue: Double(meal.calories))
            samples.append(HKQuantitySample(type: HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!, quantity: energy, start: date, end: date))
        }

        if meal.protein > 0 {
            let protein = HKQuantity(unit: .gram(), doubleValue: meal.protein)
            samples.append(HKQuantitySample(type: HKObjectType.quantityType(forIdentifier: .dietaryProtein)!, quantity: protein, start: date, end: date))
        }

        if meal.fat > 0 {
            let fat = HKQuantity(unit: .gram(), doubleValue: meal.fat)
            samples.append(HKQuantitySample(type: HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!, quantity: fat, start: date, end: date))
        }

        if meal.carbs > 0 {
            let carbs = HKQuantity(unit: .gram(), doubleValue: meal.carbs)
            samples.append(HKQuantitySample(type: HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!, quantity: carbs, start: date, end: date))
        }

        guard !samples.isEmpty else { return }

        do {
            try await healthStore.save(samples)
        } catch {
            print("Error saving meal to HealthKit: \(error.localizedDescription)")
        }
    }

    func saveWater(amountML: Int, date: Date) async {
        guard HKHealthStore.isHealthDataAvailable(), amountML > 0 else { return }

        let type = HKObjectType.quantityType(forIdentifier: .dietaryWater)!
        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: Double(amountML))
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)

        do {
            try await healthStore.save(sample)
        } catch {
            print("Error saving water to HealthKit: \(error.localizedDescription)")
        }
    }

    func saveWeight(_ weight: Double, date: Date) async {
        guard HKHealthStore.isHealthDataAvailable(), weight > 0 else { return }

        let type = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weight)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)

        do {
            try await healthStore.save(sample)
        } catch {
            print("Error saving weight to HealthKit: \(error.localizedDescription)")
        }
    }

    func fetchSteps(for date: Date) async -> Double {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        
        let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepsType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                let sum = result?.sumQuantity()
                let steps = sum?.doubleValue(for: HKUnit.count()) ?? 0
                continuation.resume(returning: steps)
            }
            healthStore.execute(query)
        }
    }

    func fetchActiveEnergyBurned(for date: Date) async -> Double {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                let sum = result?.sumQuantity()
                let kcal = sum?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
                continuation.resume(returning: kcal)
            }
            healthStore.execute(query)
        }
    }
}
