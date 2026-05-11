import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "plan-generator")

/// Generates a complete fitness plan (workouts + meals) from user preferences,
/// using the bundled FitnessLibrary. No Claude API required — fully on-device.
actor FitnessPlanGenerator {

    struct GeneratedPlan: Sendable {
        let workouts: [WorkoutItem]
        let meals: [MealItem]
        let dailyKcalTarget: Int
        let rationale: String
    }

    private let bodyProfileRepository: BodyProfileRepository

    init(bodyProfileRepository: BodyProfileRepository) {
        self.bodyProfileRepository = bodyProfileRepository
    }

    // MARK: - Entry point

    func generate(preferences: PlanPreferences) async -> GeneratedPlan {
        let profile = await bodyProfileRepository.load()
        let kcalTarget = profile.map { Int(BodyMath.dailyKcalTarget(profile: $0).dailyKcal) } ?? 2000

        let workouts = await buildWorkouts(prefs: preferences, profile: profile)
        let meals: [MealItem] = preferences.includeMealPlan
            ? await buildMeals(prefs: preferences, profile: profile, dailyKcal: Double(kcalTarget))
            : []

        var parts: [String] = []
        parts.append("\(preferences.weeks)-week \(preferences.splitStyle.displayName) plan")
        parts.append("\(preferences.daysPerWeek) workouts/week")
        if preferences.includeMealPlan {
            parts.append("\(preferences.mealsPerDay) meals/day @ ~\(kcalTarget) kcal")
        }
        if profile?.dietType != nil && profile?.dietType != .omnivore {
            parts.append("\(profile!.dietType.displayName) diet")
        }
        let rationale = parts.joined(separator: " · ")

        logger.info("Generated plan: \(workouts.count) workouts, \(meals.count) meals")
        return GeneratedPlan(workouts: workouts, meals: meals, dailyKcalTarget: kcalTarget, rationale: rationale)
    }

    // MARK: - Workouts

    private func buildWorkouts(prefs: PlanPreferences, profile: UserBodyProfile?) async -> [WorkoutItem] {
        let filter = ExerciseFilter(equipment: prefs.equipment.isEmpty ? [.bodyweight] : prefs.equipment)
        let available = await FitnessLibrary.shared.exercises(filter: filter)
        guard !available.isEmpty else { return [] }

        let sessionGroups = splitGroups(for: prefs.splitStyle, daysPerWeek: prefs.daysPerWeek)
        let cal = Calendar.current
        let bodyWeight = profile?.weightKg ?? 70

        var workouts: [WorkoutItem] = []
        for week in 0..<prefs.weeks {
            let weekOffset = week * 7
            for (dayIdx, groupNames) in sessionGroups.enumerated() {
                let stride = max(1, 7 / max(1, prefs.daysPerWeek))
                let dayOffset = dayIdx * stride
                guard let baseDay = cal.date(byAdding: .day, value: weekOffset + dayOffset, to: prefs.startDate) else { continue }
                guard let start = cal.date(bySettingHour: prefs.workoutHour, minute: 0, second: 0, of: baseDay) else { continue }
                let end = start.addingTimeInterval(TimeInterval(prefs.workoutDurationMinutes * 60))

                let exercises = pickExercises(for: groupNames, from: available, count: 4)
                guard !exercises.isEmpty else { continue }

                let avgMet = exercises.map(\.metValue).reduce(0, +) / Double(exercises.count)
                let kcal = Int(BodyMath.kcalBurned(metValue: avgMet, durationMin: prefs.workoutDurationMinutes, weightKg: bodyWeight))

                let title = sessionTitle(for: groupNames, week: week + 1, day: dayIdx + 1)
                let planned = exercises.map {
                    PlannedExercise(exerciseID: $0.id, sets: $0.defaultSets, reps: $0.defaultReps, durationMin: $0.defaultDurationMin)
                }

                workouts.append(WorkoutItem(
                    title: title,
                    notes: "\(exercises.count) exercises · \(prefs.workoutDurationMinutes) min",
                    anchor: .timeBlock(start: start, end: end),
                    plannedExercises: planned,
                    estimatedKcal: kcal
                ))
            }
        }
        return workouts
    }

    private func splitGroups(for style: SplitStyle, daysPerWeek: Int) -> [[String]] {
        switch style {
        case .fullBody:
            return Array(repeating: ["chest", "back", "quads", "core"], count: daysPerWeek)
        case .upperLower:
            let upper = ["chest", "back", "shoulders"]
            let lower = ["quads", "hamstrings", "glutes"]
            if daysPerWeek >= 4 { return [upper, lower, upper, lower] }
            return [upper, lower]
        case .pushPullLegs:
            let push = ["chest", "shoulders", "triceps"]
            let pull = ["back", "biceps"]
            let legs = ["quads", "hamstrings", "glutes", "calves"]
            var groups: [[String]] = []
            let rotation: [[String]] = [push, pull, legs]
            for i in 0..<daysPerWeek { groups.append(rotation[i % rotation.count]) }
            return groups
        case .freeform:
            return Array(repeating: ["fullBody"], count: daysPerWeek)
        }
    }

    private func pickExercises(for muscleGroupNames: [String], from exercises: [Exercise], count: Int) -> [Exercise] {
        let targets = Set(muscleGroupNames.compactMap { MuscleGroup(rawValue: $0) })
        let matches = exercises.filter { ex in
            !ex.muscleGroups.filter { targets.contains($0) }.isEmpty
        }
        let sorted = matches.sorted { $0.metValue > $1.metValue }
        return Array(sorted.prefix(count))
    }

    private func sessionTitle(for groups: [String], week: Int, day: Int) -> String {
        let pretty = groups.map { name -> String in
            switch name {
            case "fullBody": return "Full body"
            default:         return name.prefix(1).uppercased() + name.dropFirst()
            }
        }.joined(separator: " + ")
        return "W\(week) D\(day) · \(pretty)"
    }

    // MARK: - Meals

    private func buildMeals(prefs: PlanPreferences, profile: UserBodyProfile?, dailyKcal: Double) async -> [MealItem] {
        let kcalPerMeal = Int(dailyKcal / Double(prefs.mealsPerDay))
        var baseFilter = RecipeFilter()
        if let p = profile {
            baseFilter.dietType = p.dietType
            baseFilter.excludeAllergens = Set(p.allergies.map { $0.lowercased() })
        }
        let allMatching = await FitnessLibrary.shared.recipes(filter: baseFilter)
        guard !allMatching.isEmpty else { return [] }

        let mealTimes = mealTimes(for: prefs.mealsPerDay)
        let tags = mealTags(for: prefs.mealsPerDay)
        let cal = Calendar.current
        let totalDays = prefs.weeks * 7

        var meals: [MealItem] = []
        for day in 0..<totalDays {
            guard let dayDate = cal.date(byAdding: .day, value: day, to: prefs.startDate) else { continue }
            for (mealIdx, (hour, minute)) in mealTimes.enumerated() {
                let tag = tags[safe: mealIdx] ?? .snack
                let tagFilter = RecipeFilter(
                    dietType: baseFilter.dietType,
                    excludeAllergens: baseFilter.excludeAllergens,
                    mealTags: [tag],
                    maxKcal: kcalPerMeal + 200
                )
                let tagMatches = await FitnessLibrary.shared.recipes(filter: tagFilter)
                let candidates = tagMatches.isEmpty ? allMatching : tagMatches
                let recipe = candidates[(day * prefs.mealsPerDay + mealIdx) % candidates.count]

                let rawServings = Double(kcalPerMeal) / Double(max(1, recipe.kcalPerServing))
                let servings = max(0.5, min(3.0, (rawServings * 2).rounded() / 2))
                let actualKcal = Int(Double(recipe.kcalPerServing) * servings)

                guard let mealDate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: dayDate) else { continue }
                meals.append(MealItem(
                    title: recipe.name,
                    notes: "\(tag.displayName) · \(actualKcal) kcal · \(recipe.prepMin) min prep",
                    anchor: .point(mealDate),
                    recipeID: recipe.id,
                    servings: servings,
                    targetKcal: actualKcal
                ))
            }
        }
        return meals
    }

    private func mealTimes(for count: Int) -> [(Int, Int)] {
        switch count {
        case 2: return [(8, 0), (18, 0)]
        case 3: return [(8, 0), (13, 0), (19, 0)]
        case 4: return [(8, 0), (12, 0), (16, 0), (19, 0)]
        case 5: return [(8, 0), (11, 0), (14, 0), (17, 0), (20, 0)]
        case 6: return [(7, 30), (10, 0), (12, 30), (15, 0), (17, 30), (20, 0)]
        default: return [(8, 0), (13, 0), (19, 0)]
        }
    }

    private func mealTags(for count: Int) -> [MealTag] {
        switch count {
        case 2: return [.breakfast, .dinner]
        case 3: return [.breakfast, .lunch, .dinner]
        case 4: return [.breakfast, .lunch, .snack, .dinner]
        case 5: return [.breakfast, .snack, .lunch, .snack, .dinner]
        case 6: return [.breakfast, .snack, .lunch, .snack, .dinner, .snack]
        default: return [.breakfast, .lunch, .dinner]
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
