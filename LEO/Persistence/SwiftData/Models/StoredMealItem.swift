import SwiftData
import Foundation

@Model
final class StoredMealItem {
    var id: UUID
    var title: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var importanceRaw: Int
    var anchorData: Data
    var completionData: Data
    var tags: [StoredTag]?
    var recipeID: String
    var servings: Double
    var targetKcal: Int
    var actualKcal: Int?
    // Macros? stored as JSON
    var loggedMacrosData: Data?
    var healthKitCorrelationID: String?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        importanceRaw: Int = 1,
        anchorData: Data,
        completionData: Data,
        tags: [StoredTag]? = nil,
        recipeID: String,
        servings: Double = 1.0,
        targetKcal: Int = 0,
        actualKcal: Int? = nil,
        loggedMacrosData: Data? = nil,
        healthKitCorrelationID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.importanceRaw = importanceRaw
        self.anchorData = anchorData
        self.completionData = completionData
        self.tags = tags
        self.recipeID = recipeID
        self.servings = servings
        self.targetKcal = targetKcal
        self.actualKcal = actualKcal
        self.loggedMacrosData = loggedMacrosData
        self.healthKitCorrelationID = healthKitCorrelationID
    }
}
