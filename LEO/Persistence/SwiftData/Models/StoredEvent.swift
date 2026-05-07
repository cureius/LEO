import SwiftData
import Foundation

@Model
final class StoredEvent {
    var id: UUID
    var title: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var importanceRaw: Int
    var anchorData: Data
    var completionData: Data
    var tags: [StoredTag]?
    var location: String?
    // [String] stored as JSON Data to satisfy CloudKit constraints (no [String] attribute)
    var attendeesData: Data
    // ExternalRef stored as JSON
    var externalRefData: Data?

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
        location: String? = nil,
        attendeesData: Data = "[]".data(using: .utf8)!,
        externalRefData: Data? = nil
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
        self.location = location
        self.attendeesData = attendeesData
        self.externalRefData = externalRefData
    }
}
