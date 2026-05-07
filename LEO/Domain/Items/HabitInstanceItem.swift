import Foundation

/// A single materialized occurrence of a recurring Habit.
public struct HabitInstanceItem: Item {
    public let id: UUID
    public var title: String
    public var notes: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var importance: Importance
    public var anchor: Anchor
    public var completion: Completion
    public var tags: [Tag]

    /// The parent habit that spawned this instance.
    public let habitID: UUID
    public var targetDuration: Duration?

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
        habitID: UUID,
        targetDuration: Duration? = nil
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
        self.habitID = habitID
        self.targetDuration = targetDuration
    }
}
