import SwiftData
import Foundation

@Model
final class StoredAlarm {
    var id: UUID
    var title: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var importanceRaw: Int
    var anchorData: Data
    var completionData: Data
    var tags: [StoredTag]?
    var soundProfileRaw: String // AlarmSound.rawValue
    var escalates: Bool

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        importanceRaw: Int = 3,
        anchorData: Data,
        completionData: Data,
        tags: [StoredTag]? = nil,
        soundProfileRaw: String = "alarm_default",
        escalates: Bool = true
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
        self.soundProfileRaw = soundProfileRaw
        self.escalates = escalates
    }
}
