import Foundation

enum MealStyle: String, Codable, CaseIterable, Sendable {
    case balanced, highProtein, lowCarb, bulking, cutting
    var displayName: String {
        switch self {
        case .balanced:    "Balanced"
        case .highProtein: "High protein"
        case .lowCarb:     "Low carb"
        case .bulking:     "Bulking"
        case .cutting:     "Cutting"
        }
    }
}

struct ProposeMealPlanTool: LEOTool {
    struct Input: Decodable, Sendable {
        var weeks: Int?
        var mealsPerDay: Int?
        var dailyKcalTarget: Double?
        var mealStyle: String?
        var startDate: String?
    }

    struct Output: Encodable, Sendable {
        let diff: DiffPayload
        let dailyKcalTarget: Double
        let validationErrors: [String]
    }

    let definition = ToolDefinition(
        name: "propose_meal_plan",
        description: "Generate a multi-week meal plan as a Diff for user review. Selects recipes from the bundled library. Call get_body_profile first.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "weeks": .object(["type": .string("integer"), "default": .number(4)]),
                "mealsPerDay": .object(["type": .string("integer"), "default": .number(3), "description": .string("2–6 meals per day")]),
                "dailyKcalTarget": .object(["type": .string("number"), "description": .string("Override kcal target from body profile")]),
                "mealStyle": .object(["type": .string("string"), "enum": .array([.string("balanced"), .string("high_protein"), .string("low_carb"), .string("bulking"), .string("cutting")])]),
                "startDate": .object(["type": .string("string"), "description": .string("ISO8601 date. Defaults to next Monday.")])
            ]),
            "required": .array([])
        ]
    )

    private let bodyProfileRepository: BodyProfileRepository

    init(bodyProfileRepository: BodyProfileRepository) {
        self.bodyProfileRepository = bodyProfileRepository
    }

    func run(_ input: Input, context: ToolContext) async throws -> Output {
        let weeks = max(1, min(12, input.weeks ?? 4))
        let mealsPerDay = max(2, min(6, input.mealsPerDay ?? 3))

        let profile = await bodyProfileRepository.load()
        let kcalResult = profile.map { BodyMath.dailyKcalTarget(profile: $0) }
        let dailyKcal = input.dailyKcalTarget ?? kcalResult?.dailyKcal ?? 2000
        let kcalPerMeal = Int(dailyKcal / Double(mealsPerDay))

        // Build recipe filter from profile
        var recipeFilter = RecipeFilter()
        if let p = profile {
            recipeFilter.dietType = p.dietType
            recipeFilter.excludeAllergens = Set(p.allergies.map { $0.lowercased() })
        }

        let allRecipes = await FitnessLibrary.shared.recipes(filter: recipeFilter)
        guard !allRecipes.isEmpty else {
            return Output(
                diff: DiffPayload(changes: [], rationale: "No recipes found matching your dietary preferences."),
                dailyKcalTarget: dailyKcal,
                validationErrors: ["No recipes found for diet type: \(profile?.dietType.rawValue ?? "omnivore")"]
            )
        }

        let iso = ISO8601DateFormatter()
        let startDate: Date
        if let s = input.startDate, let d = iso.date(from: s) { startDate = d } else { startDate = nextMonday() }

        let mealTimes = mealTimesForCount(mealsPerDay)
        var changes: [DiffChange] = []
        var validationErrors: [String] = []

        let totalDays = weeks * 7
        for day in 0..<totalDays {
            guard let dayDate = Calendar.current.date(byAdding: .day, value: day, to: startDate) else { continue }
            let tags: [MealTag] = mealTags(for: mealsPerDay)

            for (mealIdx, (hour, minute)) in mealTimes.enumerated() {
                let tag = tags[safe: mealIdx] ?? .snack
                let tagFilter = RecipeFilter(
                    dietType: recipeFilter.dietType,
                    excludeAllergens: recipeFilter.excludeAllergens,
                    mealTags: [tag],
                    maxKcal: kcalPerMeal + 200
                )
                let candidates = await FitnessLibrary.shared.recipes(filter: tagFilter)
                let recipe = candidates.isEmpty ? allRecipes[day % allRecipes.count] : candidates[(day * mealsPerDay + mealIdx) % candidates.count]

                let servings = Double(kcalPerMeal) / Double(max(1, recipe.kcalPerServing))
                let roundedServings = max(0.5, min(3.0, (servings * 2).rounded() / 2))
                let actualKcal = Int(Double(recipe.kcalPerServing) * roundedServings)

                guard let mealDate = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: dayDate) else { continue }
                let meal = MealItem(
                    title: recipe.name,
                    anchor: .point(mealDate),
                    recipeID: recipe.id,
                    servings: roundedServings,
                    targetKcal: actualKcal
                )

                let pendingItem = PendingNewItem(
                    title: meal.title,
                    type: "meal",
                    start: iso.string(from: mealDate),
                    end: nil,
                    notes: "\(tag.displayName) — \(actualKcal) kcal — \(recipe.prepMin) min prep"
                )
                changes.append(DiffChange(
                    itemID: meal.id.uuidString,
                    kind: "add",
                    field: "title",
                    newValue: meal.title,
                    pendingItem: pendingItem
                ))
            }
        }

        // Validate recipe IDs
        let usedIDs = Set(changes.compactMap { $0.pendingItem?.notes }.flatMap { _ -> [String] in [] })
        _ = await FitnessLibrary.shared.validateRecipeIDs(Array(usedIDs))

        let dietNote = profile.map { " Diet: \($0.dietType.displayName)." } ?? ""
        let rationale = "\(weeks)-week meal plan, \(mealsPerDay) meals/day.\(dietNote) Daily target: \(Int(dailyKcal)) kcal (\(kcalPerMeal) kcal/meal)."

        return Output(diff: DiffPayload(changes: changes, rationale: rationale), dailyKcalTarget: dailyKcal, validationErrors: validationErrors)
    }

    // MARK: - Helpers

    private func nextMonday() -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        comps.weekday = 2
        let monday = cal.date(from: comps) ?? .now
        return monday > .now ? monday : cal.date(byAdding: .weekOfYear, value: 1, to: monday) ?? .now
    }

    private func mealTimesForCount(_ count: Int) -> [(Int, Int)] {
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
