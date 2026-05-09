import Foundation

// MARK: - Core types

/// RFC 5545 §3.3.10 recurrence frequency.
public enum RRuleFrequency: String, Hashable, Sendable, Codable, CaseIterable {
    case daily   = "DAILY"
    case weekly  = "WEEKLY"
    case monthly = "MONTHLY"
    case yearly  = "YEARLY"
}

/// A weekday optionally with an occurrence ordinal (e.g., 2MO = "second Monday").
public struct WeekdayOccurrence: Hashable, Sendable, Codable {
    /// nil = any occurrence of this weekday; 1 = first, -1 = last, etc.
    public let ordinal: Int?
    public let weekday: Weekday

    public init(weekday: Weekday, ordinal: Int? = nil) {
        self.weekday = weekday
        self.ordinal = ordinal
    }

    /// e.g. "MO", "2WE", "-1FR"
    public var rfcString: String {
        if let n = ordinal { return "\(n)\(weekday.rfcCode)" }
        return weekday.rfcCode
    }
}

// MARK: - RRule

/// A parsed RFC 5545 RRULE value. Supports DAILY/WEEKLY/MONTHLY/YEARLY.
/// Serializes back to a canonical RFC 5545 string via `rfc5545`.
public struct RRule: Hashable, Sendable, Codable {
    public var frequency: RRuleFrequency
    public var interval: Int                   // default 1
    public var count: Int?
    public var until: Date?
    public var byDay: [WeekdayOccurrence]      // BYDAY
    public var byMonthDay: [Int]               // BYMONTHDAY
    public var byMonth: [Int]                  // BYMONTH
    public var bySetPos: [Int]                 // BYSETPOS
    public var weekStart: Weekday              // WKST, default .monday

    public init(
        frequency: RRuleFrequency,
        interval: Int = 1,
        count: Int? = nil,
        until: Date? = nil,
        byDay: [WeekdayOccurrence] = [],
        byMonthDay: [Int] = [],
        byMonth: [Int] = [],
        bySetPos: [Int] = [],
        weekStart: Weekday = .monday
    ) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.count = count
        self.until = until
        self.byDay = byDay
        self.byMonthDay = byMonthDay
        self.byMonth = byMonth
        self.bySetPos = bySetPos
        self.weekStart = weekStart
    }

    // MARK: - Canonical RFC 5545 serialization

    public var rfc5545: String {
        var parts: [String] = ["FREQ=\(frequency.rawValue)"]
        if interval != 1 { parts.append("INTERVAL=\(interval)") }
        if !byDay.isEmpty { parts.append("BYDAY=\(byDay.map(\.rfcString).joined(separator: ","))") }
        if !byMonthDay.isEmpty { parts.append("BYMONTHDAY=\(byMonthDay.map(String.init).joined(separator: ","))") }
        if !byMonth.isEmpty { parts.append("BYMONTH=\(byMonth.map(String.init).joined(separator: ","))") }
        if !bySetPos.isEmpty { parts.append("BYSETPOS=\(bySetPos.map(String.init).joined(separator: ","))") }
        if let n = count { parts.append("COUNT=\(n)") }
        if let d = until { parts.append("UNTIL=\(isoFormatter.string(from: d))") }
        if weekStart != .monday { parts.append("WKST=\(weekStart.rfcCode)") }
        return parts.joined(separator: ";")
    }
}

// MARK: - Parser

public enum RRuleParseError: Error, Sendable {
    case emptyInput
    case missingFrequency
    case unknownKey(String)
    case invalidFrequency(String)
    case invalidByDay(String)
    case invalidInteger(String, key: String)
    case invalidDate(String)
    case conflictingCountAndUntil
}

extension RRule {
    /// Parse a raw RFC 5545 RRULE string, e.g. "FREQ=WEEKLY;BYDAY=MO,WE,FR;INTERVAL=2".
    /// The leading "RRULE:" prefix is stripped if present.
    public static func parse(_ raw: String) throws -> RRule {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.uppercased().hasPrefix("RRULE:") { s = String(s.dropFirst(6)) }
        guard !s.isEmpty else { throw RRuleParseError.emptyInput }

        var freq: RRuleFrequency? = nil
        var interval = 1
        var count: Int? = nil
        var until: Date? = nil
        var byDay: [WeekdayOccurrence] = []
        var byMonthDay: [Int] = []
        var byMonth: [Int] = []
        var bySetPos: [Int] = []
        var weekStart: Weekday = .monday

        let allowedKeys: Set<String> = [
            "FREQ","INTERVAL","COUNT","UNTIL","BYDAY","BYMONTHDAY","BYMONTH","BYSETPOS","WKST"
        ]

        for token in s.components(separatedBy: ";") {
            let parts = token.components(separatedBy: "=")
            guard parts.count == 2 else { continue }
            let key = parts[0].uppercased()
            let val = parts[1]

            guard allowedKeys.contains(key) else { throw RRuleParseError.unknownKey(key) }

            switch key {
            case "FREQ":
                guard let f = RRuleFrequency(rawValue: val.uppercased()) else {
                    throw RRuleParseError.invalidFrequency(val)
                }
                freq = f

            case "INTERVAL":
                guard let n = Int(val), n >= 1 else { throw RRuleParseError.invalidInteger(val, key: key) }
                interval = n

            case "COUNT":
                guard let n = Int(val), n >= 1 else { throw RRuleParseError.invalidInteger(val, key: key) }
                count = n

            case "UNTIL":
                guard let d = parseUntilDate(val) else { throw RRuleParseError.invalidDate(val) }
                until = d

            case "BYDAY":
                byDay = try val.components(separatedBy: ",").map { try parseWeekdayOccurrence($0) }

            case "BYMONTHDAY":
                byMonthDay = try val.components(separatedBy: ",").map {
                    guard let n = Int($0) else { throw RRuleParseError.invalidInteger($0, key: key) }
                    return n
                }

            case "BYMONTH":
                byMonth = try val.components(separatedBy: ",").map {
                    guard let n = Int($0), (1...12).contains(n) else { throw RRuleParseError.invalidInteger($0, key: key) }
                    return n
                }

            case "BYSETPOS":
                bySetPos = try val.components(separatedBy: ",").map {
                    guard let n = Int($0) else { throw RRuleParseError.invalidInteger($0, key: key) }
                    return n
                }

            case "WKST":
                guard let w = weekdayFromRFC(val.uppercased()) else { throw RRuleParseError.invalidByDay(val) }
                weekStart = w

            default: break
            }
        }

        guard let f = freq else { throw RRuleParseError.missingFrequency }
        if count != nil && until != nil { throw RRuleParseError.conflictingCountAndUntil }

        return RRule(
            frequency: f, interval: interval, count: count, until: until,
            byDay: byDay, byMonthDay: byMonthDay, byMonth: byMonth,
            bySetPos: bySetPos, weekStart: weekStart
        )
    }

    // MARK: - Private helpers

    private static func parseWeekdayOccurrence(_ s: String) throws -> WeekdayOccurrence {
        // Pattern: optional signed int prefix + 2-letter weekday code
        // e.g. "MO", "2WE", "-1FR", "+3TH"
        let pattern = #"^([+-]?\d+)?(MO|TU|WE|TH|FR|SA|SU)$"#
        guard let range = s.uppercased().range(of: pattern, options: .regularExpression) else {
            throw RRuleParseError.invalidByDay(s)
        }
        let matched = String(s.uppercased()[range])
        let code = String(matched.suffix(2))
        let ordinalStr = String(matched.dropLast(2))
        let ordinal = ordinalStr.isEmpty ? nil : Int(ordinalStr)
        guard let weekday = weekdayFromRFC(code) else { throw RRuleParseError.invalidByDay(s) }
        return WeekdayOccurrence(weekday: weekday, ordinal: ordinal)
    }

    private static func weekdayFromRFC(_ code: String) -> Weekday? {
        switch code {
        case "MO": return .monday
        case "TU": return .tuesday
        case "WE": return .wednesday
        case "TH": return .thursday
        case "FR": return .friday
        case "SA": return .saturday
        case "SU": return .sunday
        default: return nil
        }
    }

    private static func parseUntilDate(_ s: String) -> Date? {
        // Accept: YYYYMMDDTHHMMSSZ or YYYYMMDD
        for fmt in ["yyyyMMdd'T'HHmmss'Z'", "yyyyMMdd"] {
            let f = DateFormatter()
            f.dateFormat = fmt
            f.timeZone = TimeZone(identifier: "UTC")
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

// MARK: - Convenience constructors extending RecurrenceRule

extension RecurrenceRule {
    /// Build from a parsed RRule.
    public init(_ rule: RRule, extensions: [LEORuleExtension] = []) {
        self.init(raw: rule.rfc5545, extensions: extensions)
    }

    /// Parse the stored raw string back into an RRule for expansion.
    public func parsed() throws -> RRule {
        try RRule.parse(raw)
    }
}

// MARK: - Shared date formatter

private let isoFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()
