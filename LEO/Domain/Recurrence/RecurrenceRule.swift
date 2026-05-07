import Foundation

/// RFC 5545 RRULE wrapper plus LEO-specific extensions.
/// Full parsing and expansion engine is implemented in M2.
/// In M0 this is a stub that holds the raw rule string for persistence.
public struct RecurrenceRule: Hashable, Sendable, Codable {
    /// RFC 5545 RRULE string, e.g. "FREQ=WEEKLY;BYDAY=MO,WE,FR".
    public let raw: String
    public let extensions: [LEORuleExtension]

    public init(raw: String, extensions: [LEORuleExtension] = []) {
        self.raw = raw
        self.extensions = extensions
    }

    /// Convenience constructors for common rules.
    public static func daily(interval: Int = 1) -> RecurrenceRule {
        RecurrenceRule(raw: interval == 1 ? "FREQ=DAILY" : "FREQ=DAILY;INTERVAL=\(interval)")
    }

    public static func weekly(on days: [Weekday], interval: Int = 1) -> RecurrenceRule {
        let dayList = days.map(\.rfcCode).joined(separator: ",")
        let base = "FREQ=WEEKLY;BYDAY=\(dayList)"
        return RecurrenceRule(raw: interval == 1 ? base : "\(base);INTERVAL=\(interval)")
    }

    public static func monthly(dayOfMonth: Int) -> RecurrenceRule {
        RecurrenceRule(raw: "FREQ=MONTHLY;BYMONTHDAY=\(dayOfMonth)")
    }
}

/// LEO-specific scheduling extensions layered on top of standard RRULE.
public enum LEORuleExtension: String, Hashable, Sendable, Codable, CaseIterable {
    case workdaysOnly
    case skipUSHolidays
    case firstWeekdayOfMonth
}

/// ISO weekday, used to build RRULE BYDAY values.
public enum Weekday: String, Hashable, Sendable, Codable, CaseIterable {
    case monday = "MO"
    case tuesday = "TU"
    case wednesday = "WE"
    case thursday = "TH"
    case friday = "FR"
    case saturday = "SA"
    case sunday = "SU"

    var rfcCode: String { rawValue }

    var displayName: String {
        switch self {
        case .monday:    return "Mon"
        case .tuesday:   return "Tue"
        case .wednesday: return "Wed"
        case .thursday:  return "Thu"
        case .friday:    return "Fri"
        case .saturday:  return "Sat"
        case .sunday:    return "Sun"
        }
    }
}
