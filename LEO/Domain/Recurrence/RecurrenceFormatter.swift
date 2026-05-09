import Foundation

/// Converts an RRule into a human-readable English summary.
/// "Repeats daily", "Every other Tuesday and Thursday", "Monthly on the last Friday", etc.
public enum RecurrenceFormatter {

    public static func summary(for rule: RRule) -> String {
        var parts: [String] = []

        let intervalWord = intervalPrefix(rule.interval)

        switch rule.frequency {
        case .daily:
            parts.append(rule.interval == 1 ? "Daily" : "Every \(rule.interval) days")

        case .weekly:
            let dayNames = rule.byDay.isEmpty
                ? []
                : rule.byDay.map { weekdayName($0.weekday) }
            if dayNames.isEmpty {
                parts.append(rule.interval == 1 ? "Weekly" : "Every \(rule.interval) weeks")
            } else {
                let joined = listJoined(dayNames)
                parts.append("\(intervalWord.capitalized)week on \(joined)")
            }

        case .monthly:
            if !rule.byDay.isEmpty {
                let descriptions = rule.byDay.map { wo -> String in
                    if let ord = wo.ordinal {
                        return "\(ordinalWord(ord)) \(weekdayName(wo.weekday))"
                    }
                    return weekdayName(wo.weekday)
                }
                let joined = listJoined(descriptions)
                parts.append("Monthly on the \(joined)")
            } else if !rule.byMonthDay.isEmpty {
                let days = rule.byMonthDay.map { ordinalWord($0) }
                parts.append("Monthly on the \(listJoined(days))")
            } else {
                parts.append(rule.interval == 1 ? "Monthly" : "Every \(rule.interval) months")
            }

        case .yearly:
            parts.append(rule.interval == 1 ? "Yearly" : "Every \(rule.interval) years")
        }

        // End condition
        if let count = rule.count {
            parts.append("for \(count) occurrence\(count == 1 ? "" : "s")")
        } else if let until = rule.until {
            let formatted = DateFormatter.localizedString(from: until, dateStyle: .medium, timeStyle: .none)
            parts.append("until \(formatted)")
        }

        return parts.joined(separator: ", ")
    }

    // MARK: - Private helpers

    private static func intervalPrefix(_ interval: Int) -> String {
        switch interval {
        case 1: return "every "
        case 2: return "every other "
        default: return "every \(interval) "
        }
    }

    private static func weekdayName(_ wd: Weekday) -> String {
        switch wd {
        case .monday:    return "Monday"
        case .tuesday:   return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday:  return "Thursday"
        case .friday:    return "Friday"
        case .saturday:  return "Saturday"
        case .sunday:    return "Sunday"
        }
    }

    private static func ordinalWord(_ n: Int) -> String {
        let abs = Swift.abs(n)
        let suffix: String
        switch abs % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch abs % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return n < 0 ? "last" : "\(abs)\(suffix)"
    }

    private static func listJoined(_ items: [String]) -> String {
        guard !items.isEmpty else { return "" }
        guard items.count > 1 else { return items[0] }
        return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }
}
