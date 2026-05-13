import SwiftData
import Foundation

@Model
final class StoredTask {
    var id: UUID
    var title: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var importanceRaw: Int       // Importance.rawValue
    var anchorData: Data         // JSON-encoded Anchor
    var completionData: Data     // JSON-encoded Completion
    var tags: [StoredTag]?
    var deadline: Date?
    var estimatedDurationSeconds: Double? // Duration.components.seconds equivalent
    var rruleRaw: String?

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
        deadline: Date? = nil,
        estimatedDurationSeconds: Double? = nil,
        rruleRaw: String? = nil
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
        self.deadline = deadline
        self.estimatedDurationSeconds = estimatedDurationSeconds
        self.rruleRaw = rruleRaw
    }
}
