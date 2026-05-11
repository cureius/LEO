import SwiftData
import Foundation

@Model
final class StoredWorkoutItem {
    var id: UUID
    var title: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var importanceRaw: Int
    var anchorData: Data
    var completionData: Data
    var tags: [StoredTag]?
    // [PlannedExercise] as JSON
    var plannedExercisesData: Data
    var estimatedKcal: Int
    var actualKcal: Int?
    // [LoggedExercise]? as JSON
    var actualExercisesData: Data?
    var healthKitWorkoutID: String?

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
        plannedExercisesData: Data = "[]".data(using: .utf8)!,
        estimatedKcal: Int = 0,
        actualKcal: Int? = nil,
        actualExercisesData: Data? = nil,
        healthKitWorkoutID: String? = nil
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
        self.plannedExercisesData = plannedExercisesData
        self.estimatedKcal = estimatedKcal
        self.actualKcal = actualKcal
        self.actualExercisesData = actualExercisesData
        self.healthKitWorkoutID = healthKitWorkoutID
    }
}
