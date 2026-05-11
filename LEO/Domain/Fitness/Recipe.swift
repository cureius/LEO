import Foundation

public struct Macros: Hashable, Sendable, Codable {
    public var proteinG: Double
    public var carbG: Double
    public var fatG: Double

    public init(proteinG: Double, carbG: Double, fatG: Double) {
        self.proteinG = proteinG
        self.carbG = carbG
        self.fatG = fatG
    }

    /// Computed kcal using 4-4-9 rule.
    public var computedKcal: Double { proteinG * 4 + carbG * 4 + fatG * 9 }
}

public enum MealTag: String, Codable, CaseIterable, Hashable, Sendable {
    case breakfast, lunch, dinner, snack, preworkout, postworkout
    var displayName: String {
        switch self {
        case .breakfast:   "Breakfast"
        case .lunch:       "Lunch"
        case .dinner:      "Dinner"
        case .snack:       "Snack"
        case .preworkout:  "Pre-workout"
        case .postworkout: "Post-workout"
        }
    }
}

public struct Ingredient: Hashable, Sendable, Codable {
    public let name: String
    public let amount: String

    public init(name: String, amount: String) {
        self.name = name
        self.amount = amount
    }
}

public struct Recipe: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let dietTags: [DietType]
    public let allergens: [String]
    public let kcalPerServing: Int
    public let macros: Macros
    public let ingredients: [Ingredient]
    public let instructions: String
    public let prepMin: Int
    public let tags: [MealTag]
}

// MARK: - Filter

public struct RecipeFilter: Sendable {
    public var dietType: DietType?
    public var excludeAllergens: Set<String>
    public var mealTags: Set<MealTag>
    public var maxKcal: Int?

    public init(
        dietType: DietType? = nil,
        excludeAllergens: Set<String> = [],
        mealTags: Set<MealTag> = [],
        maxKcal: Int? = nil
    ) {
        self.dietType = dietType
        self.excludeAllergens = excludeAllergens
        self.mealTags = mealTags
        self.maxKcal = maxKcal
    }

    func matches(_ recipe: Recipe) -> Bool {
        if let d = dietType, !recipe.dietTags.contains(d) { return false }
        if !excludeAllergens.isEmpty && recipe.allergens.contains(where: { excludeAllergens.contains($0) }) { return false }
        if !mealTags.isEmpty && recipe.tags.allSatisfy({ !mealTags.contains($0) }) { return false }
        if let max = maxKcal, recipe.kcalPerServing > max { return false }
        return true
    }
}
