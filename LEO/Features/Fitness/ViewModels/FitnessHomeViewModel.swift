import Foundation
import Observation

@Observable
@MainActor
final class FitnessHomeViewModel {
    var profile: UserBodyProfile? = nil
    var measurements: [BodyMeasurement] = []
    var todayWorkouts: [WorkoutItem] = []
    var todayMeals: [MealItem] = []
    var weekWorkouts: [WorkoutItem] = []
    var weekMeals: [MealItem] = []
    var isLoading = false
    var errorMessage: String? = nil

    // Computed kcal stats for today
    var kcalIn: Int {
        todayMeals.filter(\.isCompleted).reduce(0) { $0 + $1.displayKcal }
    }

    var kcalOut: Int {
        let bmr = profile.map { BodyMath.bmr(profile: $0) / 24 * hoursInDay } ?? 0
        let workoutKcal = todayWorkouts.filter(\.isCompleted).reduce(0.0) { $0 + Double($1.displayKcal) }
        return Int(bmr + workoutKcal)
    }

    var kcalDelta: Int {
        guard let p = profile else { return 0 }
        let target = Int(BodyMath.dailyKcalTarget(profile: p).dailyKcal)
        return kcalIn - target
    }

    var weekAdherenceRatio: Double {
        let expected = weekWorkouts.count
        guard expected > 0 else { return 0 }
        let done = weekWorkouts.filter(\.isCompleted).count
        return Double(done) / Double(expected)
    }

    private var hoursInDay: Double {
        let hour = Calendar.current.component(.hour, from: .now)
        return Double(hour) + 1
    }

    // MARK: - Dependencies

    private let itemRepository: ItemRepository
    private let bodyProfileRepository: BodyProfileRepository

    init(itemRepository: ItemRepository, bodyProfileRepository: BodyProfileRepository) {
        self.itemRepository = itemRepository
        self.bodyProfileRepository = bodyProfileRepository
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let profileLoad = bodyProfileRepository.load()
        async let measurementsLoad = bodyProfileRepository.recentMeasurements(limit: 90)
        async let itemsLoad: [any Item]? = try? itemRepository.fetch(predicate: .all)

        profile = await profileLoad
        measurements = await measurementsLoad

        if let items = await itemsLoad {
            let today = Calendar.current.startOfDay(for: .now)
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
            let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today

            todayWorkouts = items.compactMap { $0 as? WorkoutItem }.filter { w in
                guard let d = w.anchor.sortDate else { return false }
                return d >= today && d < tomorrow
            }
            todayMeals = items.compactMap { $0 as? MealItem }.filter { m in
                guard let d = m.anchor.sortDate else { return false }
                return d >= today && d < tomorrow
            }
            weekWorkouts = items.compactMap { $0 as? WorkoutItem }.filter { w in
                guard let d = w.anchor.sortDate else { return false }
                return d >= today && d < weekEnd
            }
            weekMeals = items.compactMap { $0 as? MealItem }.filter { m in
                guard let d = m.anchor.sortDate else { return false }
                return d >= today && d < weekEnd
            }
        }
    }

    // MARK: - Actions

    func completeWorkout(_ workout: WorkoutItem) async {
        var updated = workout
        updated.completion = .completed(at: .now)
        updated.actualKcal = workout.estimatedKcal
        do { try await itemRepository.update(updated) } catch { errorMessage = error.localizedDescription }
        await load()
    }

    func completeMeal(_ meal: MealItem, servings: Double? = nil) async {
        var updated = meal
        updated.completion = .completed(at: .now)
        if let s = servings { updated.servings = s }
        updated.actualKcal = Int(Double(meal.targetKcal) * (servings ?? meal.servings) / meal.servings)
        do { try await itemRepository.update(updated) } catch { errorMessage = error.localizedDescription }
        await load()
    }

    func addMeasurement(weightKg: Double, bodyFatPct: Double?) async {
        let m = BodyMeasurement(weightKg: weightKg, bodyFatPct: bodyFatPct, source: .manual)
        do {
            try await bodyProfileRepository.appendMeasurement(m)
            // Update current weight in profile
            if var p = profile {
                p.weightKg = weightKg
                if let fat = bodyFatPct { p.bodyFatPct = fat }
                try await bodyProfileRepository.save(p)
            }
        } catch { errorMessage = error.localizedDescription }
        await load()
    }
}
