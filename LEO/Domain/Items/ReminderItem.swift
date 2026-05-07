import Foundation

/// A point-in-time or location-triggered notification.
public struct ReminderItem: Item {
    public let id: UUID
    public var title: String
    public var notes: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var importance: Importance
    public var anchor: Anchor
    public var completion: Completion
    public var tags: [Tag]

    /// How far before the anchor to fire the reminder (e.g., 600 = 10 min before).
    public var leadTime: TimeInterval?
    public var externalRef: ExternalRef?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        importance: Importance = .normal,
        anchor: Anchor,
        completion: Completion = .open,
        tags: [Tag] = [],
        leadTime: TimeInterval? = nil,
        externalRef: ExternalRef? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.importance = importance
        self.anchor = anchor
        self.completion = completion
        self.tags = tags
        self.leadTime = leadTime
        self.externalRef = externalRef
    }
}
