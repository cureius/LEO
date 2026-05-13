import Foundation

/// A time-blocked calendar event with optional location and attendees.
public struct EventItem: Item {
    public let id: UUID
    public var title: String
    public var notes: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var importance: Importance
    public var anchor: Anchor
    public var completion: Completion
    public var tags: [Tag]

    /// Human-readable address or venue name.
    public var location: String?
    /// Names or email addresses; no Contacts integration in v1.
    public var attendees: [String]
    /// External calendar/event reference for EventKit-sourced items.
    public var externalRef: ExternalRef?
    public var rruleRaw: String?

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
        location: String? = nil,
        attendees: [String] = [],
        externalRef: ExternalRef? = nil,
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
        self.location = location
        self.attendees = attendees
        self.externalRef = externalRef
        self.rruleRaw = rruleRaw
    }
}

/// Reference to an item sourced from an external system (EventKit, etc.).
public struct ExternalRef: Hashable, Sendable, Codable {
    public enum Source: String, Hashable, Sendable, Codable { case eventKit }
    public let source: Source
    public let identifier: String
    public let lastSeen: Date

    public init(source: Source, identifier: String, lastSeen: Date = .now) {
        self.source = source
        self.identifier = identifier
        self.lastSeen = lastSeen
    }
}
