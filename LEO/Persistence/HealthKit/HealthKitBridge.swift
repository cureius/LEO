import Foundation
import HealthKit
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "healthkit")

struct BodyMetricsSnapshot: Sendable {
    var weightKg: Double?
    var bodyFatPct: Double?
    var heightCm: Double?
    var dateOfBirth: Date?
    var biologicalSex: BiologicalSex?
}

actor HealthKitBridge {
    private let store = HKHealthStore()
    private var observerQueryTask: Task<Void, Never>?

    nonisolated var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Read types

    private let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = []
        let quantityIDs: [HKQuantityTypeIdentifier] = [
            .bodyMass, .bodyFatPercentage, .height,
            .activeEnergyBurned, .appleExerciseTime,
            .dietaryEnergyConsumed, .dietaryProtein,
            .dietaryCarbohydrates, .dietaryFatTotal
        ]
        for id in quantityIDs {
            if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { types.insert(dob) }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { types.insert(sex) }
        types.insert(HKObjectType.workoutType())
        if let correlation = HKObjectType.correlationType(forIdentifier: .food) { types.insert(correlation) }
        return types
    }()

    private let writeTypes: Set<HKSampleType> = {
        var types: Set<HKSampleType> = []
        let quantityIDs: [HKQuantityTypeIdentifier] = [
            .activeEnergyBurned,
            .dietaryEnergyConsumed, .dietaryProtein,
            .dietaryCarbohydrates, .dietaryFatTotal
        ]
        for id in quantityIDs {
            if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        types.insert(HKObjectType.workoutType())
        if let correlation = HKObjectType.correlationType(forIdentifier: .food) { types.insert(correlation) }
        return types
    }()

    // MARK: - Authorization

    /// Detailed outcome of an authorization attempt so the UI can show the right message.
    enum AuthOutcome: Sendable {
        case granted                  // user said yes
        case denied                   // user said no
        case unavailable              // device has no HealthKit
        case entitlementMissing       // app binary lacks HealthKit entitlement (debug builds)
        case timedOut                 // HK daemon did not respond within the budget
        case error(String)            // HK threw an explicit error
    }

    func requestAccess() async -> AuthOutcome {
        guard isAvailable else {
            logger.info("HealthKit not available on this device")
            return .unavailable
        }
        // Use the completion-handler API so we can race a strict timeout
        // against the HK daemon. The async wrapper has occasionally been
        // observed to silently never resume when the entitlement is missing.
        let shareTypes = self.writeTypes
        let readTypes  = self.readTypes
        let hkStore    = self.store

        return await withCheckedContinuation { (continuation: CheckedContinuation<AuthOutcome, Never>) in
            let state = ResumeOnce<AuthOutcome>()

            // 5-second timeout — long enough for the user to interact with the
            // system permission sheet, short enough to surface entitlement bugs.
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                state.resume(continuation, with: .timedOut)
            }

            hkStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
                if let error = error as NSError? {
                    // HKError code 4 == HKErrorAuthorizationNotDetermined — usually entitlement missing
                    let outcome: AuthOutcome
                    if error.domain == "com.apple.healthkit" && error.code == 4 {
                        outcome = .entitlementMissing
                    } else {
                        outcome = .error(error.localizedDescription)
                    }
                    state.resume(continuation, with: outcome)
                    return
                }
                // success == true means the user interacted with the sheet (granted or denied).
                // We can't tell granted vs denied directly from this callback; rely on the
                // post-call status query instead. Return .granted as a hopeful default; the
                // caller verifies via authorizationStatus().
                state.resume(continuation, with: success ? .granted : .denied)
            }
        }
    }

    func authorizationStatus() async -> HKAuthorizationStatus {
        guard isAvailable else { return .notDetermined }
        return store.authorizationStatus(for: HKObjectType.workoutType())
    }

    // MARK: - Read body metrics

    func readBodyMetrics() async throws -> BodyMetricsSnapshot {
        guard isAvailable else { return BodyMetricsSnapshot() }
        async let weight = latestQuantity(typeID: .bodyMass)
        async let fat = latestQuantity(typeID: .bodyFatPercentage)
        async let height = latestQuantity(typeID: .height)

        var snapshot = BodyMetricsSnapshot()
        snapshot.weightKg = try await weight.map { $0.doubleValue(for: .gramUnit(with: .kilo)) }
        snapshot.bodyFatPct = try await fat.map { $0.doubleValue(for: .percent()) * 100 }
        snapshot.heightCm = try await height.map { $0.doubleValue(for: .meterUnit(with: .centi)) }

        if let dob = try? store.dateOfBirthComponents().date { snapshot.dateOfBirth = dob }
        if let sex = try? store.biologicalSex().biologicalSex {
            switch sex {
            case .male:   snapshot.biologicalSex = .male
            case .female: snapshot.biologicalSex = .female
            default:      snapshot.biologicalSex = .other
            }
        }
        return snapshot
    }

    private func latestQuantity(typeID: HKQuantityTypeIdentifier) async throws -> HKQuantity? {
        guard let type = HKQuantityType.quantityType(forIdentifier: typeID) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (samples?.first as? HKQuantitySample)?.quantity)
            }
            store.execute(query)
        }
    }

    // MARK: - Read active energy today

    func readActiveEnergyToday() async throws -> Double {
        guard isAvailable, let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error { continuation.resume(throwing: error); return }
                let kcal = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: kcal)
            }
            store.execute(query)
        }
    }

    // MARK: - Write workout

    /// Writes a completed WorkoutItem to Apple Health using HKWorkoutBuilder. Returns the HKWorkout UUID string.
    func writeWorkout(_ item: WorkoutItem) async throws -> String {
        guard isAvailable else { throw HealthKitError.notAvailable }
        let activityType = workoutActivityType(for: item)
        guard case .timeBlock(let start, let end) = item.anchor else {
            throw HealthKitError.missingTimeBlock
        }
        let kcal = Double(item.displayKcal)

        let config = HKWorkoutConfiguration()
        config.activityType = activityType
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: nil)
        try await builder.beginCollection(at: start)

        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let energySample = HKQuantitySample(
                type: energyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                start: start, end: end
            )
            try await builder.addSamples([energySample])
        }

        try await builder.endCollection(at: end)
        guard let workout = try await builder.finishWorkout() else {
            throw HealthKitError.notAvailable
        }
        logger.info("HKWorkout saved: \(workout.uuid)")
        return workout.uuid.uuidString
    }

    // MARK: - Write meal

    /// Writes a completed MealItem to Apple Health as an HKCorrelation. Returns correlation UUID string.
    func writeMeal(_ item: MealItem) async throws -> String {
        guard isAvailable else { throw HealthKitError.notAvailable }
        let kcal = Double(item.displayKcal)
        let mealDate: Date
        if case .point(let d) = item.anchor { mealDate = d } else { mealDate = .now }

        let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
        let energySample = HKQuantitySample(
            type: energyType,
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
            start: mealDate, end: mealDate
        )
        var samples: [HKSample] = [energySample]
        if let macros = item.loggedMacros {
            if let t = HKQuantityType.quantityType(forIdentifier: .dietaryProtein) {
                samples.append(HKQuantitySample(type: t, quantity: HKQuantity(unit: .gram(), doubleValue: macros.proteinG), start: mealDate, end: mealDate))
            }
            if let t = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) {
                samples.append(HKQuantitySample(type: t, quantity: HKQuantity(unit: .gram(), doubleValue: macros.carbG), start: mealDate, end: mealDate))
            }
            if let t = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal) {
                samples.append(HKQuantitySample(type: t, quantity: HKQuantity(unit: .gram(), doubleValue: macros.fatG), start: mealDate, end: mealDate))
            }
        }
        let foodType = HKCorrelationType.correlationType(forIdentifier: .food)!
        let correlation = HKCorrelation(
            type: foodType,
            start: mealDate,
            end: mealDate,
            objects: Set(samples),
            metadata: ["LEO_ID": item.id.uuidString, "LEO_RECIPE": item.recipeID]
        )
        try await store.save(correlation)
        logger.info("HKCorrelation (meal) saved: \(correlation.uuid)")
        return correlation.uuid.uuidString
    }

    // MARK: - Delete

    func deleteHealthRecord(uuid: String) async throws {
        guard isAvailable, let id = UUID(uuidString: uuid) else { return }
        let predicate = HKQuery.predicateForObject(with: id)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.store.deleteObjects(of: HKObjectType.workoutType(), predicate: predicate) { _, _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    // MARK: - Observer

    func startObservingBodyMetrics(onChange: @escaping @Sendable () async -> Void) {
        observerQueryTask?.cancel()
        observerQueryTask = Task {
            guard isAvailable, let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
            do {
                try await store.enableBackgroundDelivery(for: type, frequency: .immediate)
                let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                    guard error == nil else { completion(); return }
                    Task { await onChange(); completion() }
                }
                store.execute(query)
            } catch {
                logger.error("HealthKit observer setup failed: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func workoutActivityType(for item: WorkoutItem) -> HKWorkoutActivityType {
        // Default to strength training; future versions can look up muscle groups via FitnessLibrary
        let titleLower = item.title.lowercased()
        if titleLower.contains("run") || titleLower.contains("cardio") || titleLower.contains("jog") { return .running }
        if titleLower.contains("cycle") || titleLower.contains("bike") { return .cycling }
        if titleLower.contains("yoga") { return .yoga }
        if titleLower.contains("swim") { return .swimming }
        if titleLower.contains("walk") { return .walking }
        return .traditionalStrengthTraining
    }
}

/// Thread-safe single-shot continuation resumer. Used so a timeout DispatchWorkItem
/// and the HealthKit completion callback can race without ever resuming the
/// continuation twice (which would trap).
final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ continuation: CheckedContinuation<T, Never>, with value: T) {
        lock.lock()
        let canResume = !resumed
        resumed = true
        lock.unlock()
        if canResume { continuation.resume(returning: value) }
    }
}

enum HealthKitError: Error, LocalizedError {
    case notAvailable
    case missingTimeBlock

    var errorDescription: String? {
        switch self {
        case .notAvailable:    "HealthKit is not available on this device."
        case .missingTimeBlock: "Workout must have a time-block anchor to write to HealthKit."
        }
    }
}
