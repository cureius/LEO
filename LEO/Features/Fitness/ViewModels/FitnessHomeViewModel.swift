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

    // MARK: - Kcal stats

    var kcalIn: Int {
        todayMeals.filter(\.isCompleted).reduce(0) { $0 + $1.displayKcal }
    }

    /// Calories burned from completed workouts today only (no BMR blending).
    var kcalBurned: Int {
        todayWorkouts.filter(\.isCompleted).reduce(0) { $0 + $1.displayKcal }
    }

    var kcalTarget: Int {
        profile.map { Int(BodyMath.dailyKcalTarget(profile: $0).dailyKcal) } ?? 2000
    }

    /// Positive = surplus vs goal, negative = deficit.
    var kcalDelta: Int { kcalIn - kcalTarget }

    /// 0…1 fraction of today's calorie target consumed.
    var kcalProgress: Double {
        guard kcalTarget > 0 else { return 0 }
        return min(1, Double(kcalIn) / Double(kcalTarget))
    }

    // MARK: - Weekly data

    /// Mon–Sun of the current ISO week.
    var weekDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekday = cal.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: today)!
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday)! }
    }

    var weekAdherenceRatio: Double {
        let expected = weekWorkouts.count
        guard expected > 0 else { return 0 }
        return Double(weekWorkouts.filter(\.isCompleted).count) / Double(expected)
    }

    func workouts(on day: Date) -> [WorkoutItem] {
        weekWorkouts.filter { w in
            guard let d = w.anchor.sortDate else { return false }
            return Calendar.current.isDate(d, inSameDayAs: day)
        }
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

        guard let items = await itemsLoad else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        // Cover Mon–Sun of current week so weekDays strip has full coverage.
        let days = weekDays
        let weekStart = days.first ?? today
        let weekEnd = cal.date(byAdding: .day, value: 1, to: days.last ?? today)!

        todayWorkouts = items.compactMap { $0 as? WorkoutItem }.filter { w in
            guard let d = w.anchor.sortDate else { return false }
            return d >= today && d < tomorrow
        }.sorted { ($0.anchor.sortDate ?? .distantFuture) < ($1.anchor.sortDate ?? .distantFuture) }

        todayMeals = items.compactMap { $0 as? MealItem }.filter { m in
            guard let d = m.anchor.sortDate else { return false }
            return d >= today && d < tomorrow
        }.sorted { ($0.anchor.sortDate ?? .distantFuture) < ($1.anchor.sortDate ?? .distantFuture) }

        weekWorkouts = items.compactMap { $0 as? WorkoutItem }.filter { w in
            guard let d = w.anchor.sortDate else { return false }
            return d >= weekStart && d < weekEnd
        }

        weekMeals = items.compactMap { $0 as? MealItem }.filter { m in
            guard let d = m.anchor.sortDate else { return false }
            return d >= weekStart && d < weekEnd
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

    func uncompleteWorkout(_ workout: WorkoutItem) async {
        var updated = workout
        updated.completion = .open
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
            if var p = profile {
                p.weightKg = weightKg
                if let fat = bodyFatPct { p.bodyFatPct = fat }
                try await bodyProfileRepository.save(p)
            }
        } catch { errorMessage = error.localizedDescription }
        await load()
    }
}
