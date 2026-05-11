import Foundation

/// A single meal slot in the user's plan.
/// Anchor: `.point(date)` — the planned meal time.
public struct MealItem: Item {
    public let id: UUID
    public var title: String
    public var notes: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var importance: Importance
    public var anchor: Anchor
    public var completion: Completion
    public var tags: [Tag]

    public var recipeID: String
    public var servings: Double
    public var targetKcal: Int
    public var actualKcal: Int?
    public var loggedMacros: Macros?
    public var healthKitCorrelationID: String?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        importance: Importance = .normal,
        anchor: Anchor = .untimed,
        completion: Completion = .open,
        tags: [Tag] = [],
        recipeID: String,
        servings: Double = 1.0,
        targetKcal: Int = 0,
        actualKcal: Int? = nil,
        loggedMacros: Macros? = nil,
        healthKitCorrelationID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.importance = importance
        self.anchor = anchor
        self.completion = completion
        var t = tags
        if !t.contains(where: { $0.name == "#meal" }) {
            t.append(Tag(name: "#meal"))
        }
        self.tags = t
        self.recipeID = recipeID
        self.servings = servings
        self.targetKcal = targetKcal
        self.actualKcal = actualKcal
        self.loggedMacros = loggedMacros
        self.healthKitCorrelationID = healthKitCorrelationID
    }

    public var displayKcal: Int { actualKcal ?? targetKcal }
}
