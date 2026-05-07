import SwiftData
import Foundation

@Model
final class StoredHabitInstance {
    var id: UUID
    var title: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var importanceRaw: Int
    var anchorData: Data
    var completionData: Data
    var tags: [StoredTag]?
    var habitID: UUID
    var targetDurationSeconds: Double?

    var habit: StoredHabit?

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
        habitID: UUID,
        targetDurationSeconds: Double? = nil
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
        self.habitID = habitID
        self.targetDurationSeconds = targetDurationSeconds
    }
}
