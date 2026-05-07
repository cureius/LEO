import Foundation

/// A habit definition. Spawns `HabitInstanceItem`s via the materializer.
public struct Habit: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var frequency: HabitFrequency
    public var timeHint: TimeOfDay?
    public var targetDuration: Duration?
    public var recurrenceRule: RecurrenceRule
    public var forgiveness: HabitForgiveness
    public let createdAt: Date
    public var isArchived: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        frequency: HabitFrequency,
        timeHint: TimeOfDay? = nil,
        targetDuration: Duration? = nil,
        recurrenceRule: RecurrenceRule,
        forgiveness: HabitForgiveness = .misses(perWeek: 1),
        createdAt: Date = .now,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.frequency = frequency
        self.timeHint = timeHint
        self.targetDuration = targetDuration
        self.recurrenceRule = recurrenceRule
        self.forgiveness = forgiveness
        self.createdAt = createdAt
        self.isArchived = isArchived
    }
}

// MARK: - HabitFrequency

public enum HabitFrequency: Hashable, Sendable, Codable {
    case daily
    case timesPerWeek(Int)
    case specificDays([Weekday])
    case custom(RecurrenceRule)

    enum CodingKeys: String, CodingKey { case type, count, days, rule }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily:
            try c.encode("daily", forKey: .type)
        case .timesPerWeek(let n):
            try c.encode("timesPerWeek", forKey: .type)
            try c.encode(n, forKey: .count)
        case .specificDays(let days):
            try c.encode("specificDays", forKey: .type)
            try c.encode(days, forKey: .days)
        case .custom(let rule):
            try c.encode("custom", forKey: .type)
            try c.encode(rule, forKey: .rule)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "timesPerWeek":
            self = .timesPerWeek(try c.decode(Int.self, forKey: .count))
        case "specificDays":
            self = .specificDays(try c.decode([Weekday].self, forKey: .days))
        case "custom":
            self = .custom(try c.decode(RecurrenceRule.self, forKey: .rule))
        default:
            self = .daily
        }
    }
}

// MARK: - TimeOfDay

public enum TimeOfDay: Hashable, Sendable, Codable {
    case morning
    case afternoon
    case evening
    case specific(hour: Int, minute: Int)

    var hintHour: Int {
        switch self {
        case .morning:            return 7
        case .afternoon:          return 13
        case .evening:            return 19
        case .specific(let h, _): return h
        }
    }

    var displayName: String {
        switch self {
        case .morning:   return "Morning"
        case .afternoon: return "Afternoon"
        case .evening:   return "Evening"
        case .specific(let h, let m): return String(format: "%d:%02d", h, m)
        }
    }

    // MARK: Codable
    enum CodingKeys: String, CodingKey { case type, hour, minute }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .morning:   try c.encode("morning", forKey: .type)
        case .afternoon: try c.encode("afternoon", forKey: .type)
        case .evening:   try c.encode("evening", forKey: .type)
        case .specific(let h, let m):
            try c.encode("specific", forKey: .type)
            try c.encode(h, forKey: .hour)
            try c.encode(m, forKey: .minute)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "afternoon": self = .afternoon
        case "evening":   self = .evening
        case "specific":
            self = .specific(
                hour: try c.decode(Int.self, forKey: .hour),
                minute: try c.decode(Int.self, forKey: .minute)
            )
        default: self = .morning
        }
    }
}

// MARK: - HabitForgiveness

public enum HabitForgiveness: Hashable, Sendable, Codable {
    case none
    case misses(perWeek: Int)
    case percent(minimum: Double)

    enum CodingKeys: String, CodingKey { case type, count, value }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try c.encode("none", forKey: .type)
        case .misses(let n):
            try c.encode("misses", forKey: .type)
            try c.encode(n, forKey: .count)
        case .percent(let v):
            try c.encode("percent", forKey: .type)
            try c.encode(v, forKey: .value)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "misses":  self = .misses(perWeek: try c.decode(Int.self, forKey: .count))
        case "percent": self = .percent(minimum: try c.decode(Double.self, forKey: .value))
        default:        self = .none
        }
    }
}
