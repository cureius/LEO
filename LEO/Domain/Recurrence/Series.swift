import Foundation

/// A recurring series: the abstract template + expansion rule + per-occurrence overrides.
/// Concrete occurrences (TaskItem, EventItem, HabitInstanceItem, etc.) are generated
/// by `RecurrenceEngine` from `rule` + `anchorStart`, then filtered through `overrides`.
public struct Series: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let rule: RRule
    public let anchorStart: Date
    public let extensions: [LEORuleExtension]
    /// Keyed by the *canonical* occurrence date (i.e., the date the engine produces before any override).
    public var overrides: [Date: SeriesOverride]

    public init(
        id: UUID = UUID(),
        rule: RRule,
        anchorStart: Date,
        extensions: [LEORuleExtension] = [],
        overrides: [Date: SeriesOverride] = [:]
    ) {
        self.id = id
        self.rule = rule
        self.anchorStart = anchorStart
        self.extensions = extensions
        self.overrides = overrides
    }

    // MARK: - Override application

    /// Returns only the non-skipped dates, with moved dates remapped.
    public func applyOverrides(to dates: [Date]) -> [Date] {
        var result: [Date] = []
        for date in dates {
            switch overrides[date] {
            case .skip:
                break
            case .move(let start, _):
                result.append(start)
            case .fieldsOnly, nil:
                result.append(date)
            }
        }
        return result.sorted()
    }
}

// MARK: - Override kinds

public enum SeriesOverride: Hashable, Sendable, Codable {
    /// Remove this one occurrence entirely.
    case skip(reason: String?)
    /// Reschedule just this occurrence to a different time block.
    case move(start: Date, end: Date)
    /// Override item fields (title, notes, etc.) without changing the time.
    case fieldsOnly(ItemPatch)

    public var movedInterval: DateInterval? {
        guard case .move(let s, let e) = self else { return nil }
        return DateInterval(start: s, end: e)
    }
}

// MARK: - ItemPatch Codable

extension ItemPatch: Codable {
    enum CodingKeys: String, CodingKey {
        case title, notes, importance, anchor, completion, tags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title      = try c.decodeIfPresent(String.self, forKey: .title)
        notes      = try c.decodeIfPresent(String?.self, forKey: .notes)
        importance = try c.decodeIfPresent(Importance.self, forKey: .importance)
        anchor     = try c.decodeIfPresent(Anchor.self, forKey: .anchor)
        completion = try c.decodeIfPresent(Completion.self, forKey: .completion)
        tags       = try c.decodeIfPresent([Tag].self, forKey: .tags)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        if let notes { try c.encode(notes, forKey: .notes) }
        try c.encodeIfPresent(importance, forKey: .importance)
        try c.encodeIfPresent(anchor, forKey: .anchor)
        try c.encodeIfPresent(completion, forKey: .completion)
        try c.encodeIfPresent(tags, forKey: .tags)
    }
}
