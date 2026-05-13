import Foundation

/// An open-ended work item with an optional deadline.
/// `deadline` is the hard date even if work is scheduled earlier via `anchor`.
public struct TaskItem: Item {
    public let id: UUID
    public var title: String
    public var notes: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var importance: Importance
    public var anchor: Anchor
    public var completion: Completion
    public var tags: [Tag]

    /// The hard due date (distinct from anchor, which may be a scheduled work block before this).
    public var deadline: Date?
    public var estimatedDuration: Duration?
    public var rruleRaw: String?

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
        deadline: Date? = nil,
        estimatedDuration: Duration? = nil,
        rruleRaw: String? = nil
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
        self.deadline = deadline
        self.estimatedDuration = estimatedDuration
        self.rruleRaw = rruleRaw
    }
}
