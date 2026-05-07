import Foundation

/// An alarm that overrides the silent switch (best-effort on iOS).
public struct AlarmItem: Item {
    public let id: UUID
    public var title: String
    public var notes: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var importance: Importance
    public var anchor: Anchor
    public var completion: Completion
    public var tags: [Tag]

    public var soundProfile: AlarmSound
    /// If true, volume escalates from low to max over 30s.
    public var escalates: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        importance: Importance = .urgent,
        anchor: Anchor,
        completion: Completion = .open,
        tags: [Tag] = [],
        soundProfile: AlarmSound = .default,
        escalates: Bool = true
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
        self.soundProfile = soundProfile
        self.escalates = escalates
    }
}

public enum AlarmSound: String, Hashable, Sendable, Codable, CaseIterable {
    case `default` = "alarm_default"
    case gentle = "alarm_gentle"
    case urgent = "alarm_urgent"
    case bell = "alarm_bell"
    case chime = "alarm_chime"
    case hapticOnly = "haptic_only"

    var displayName: String {
        switch self {
        case .default:    return "Default"
        case .gentle:     return "Gentle"
        case .urgent:     return "Urgent"
        case .bell:       return "Bell"
        case .chime:      return "Chime"
        case .hapticOnly: return "Haptic Only"
        }
    }
}
