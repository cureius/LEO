import Foundation

/// Determines whether a date falls on a US federal holiday (observed).
/// "Observed" rule: if the holiday falls on Saturday, observed the preceding Friday;
/// if it falls on Sunday, observed the following Monday.
public enum USFederalHolidays {

    public static func isHoliday(_ date: Date, cal: Calendar) -> Bool {
        let year = cal.component(.year, from: date)
        return holidays(for: year, cal: cal).contains { cal.isDate($0, inSameDayAs: date) }
    }

    /// All 11 federal holidays (observed dates) for a given year.
    public static func holidays(for year: Int, cal: Calendar) -> [Date] {
        var results: [Date] = []

        // New Year's Day — Jan 1
        results.append(observed(month: 1, day: 1, year: year, cal: cal))

        // Martin Luther King Jr. Day — 3rd Monday of January
        results.append(nthWeekday(.monday, n: 3, month: 1, year: year, cal: cal))

        // Presidents' Day — 3rd Monday of February
        results.append(nthWeekday(.monday, n: 3, month: 2, year: year, cal: cal))

        // Memorial Day — last Monday of May
        results.append(lastWeekday(.monday, month: 5, year: year, cal: cal))

        // Juneteenth — Jun 19
        results.append(observed(month: 6, day: 19, year: year, cal: cal))

        // Independence Day — Jul 4
        results.append(observed(month: 7, day: 4, year: year, cal: cal))

        // Labor Day — 1st Monday of September
        results.append(nthWeekday(.monday, n: 1, month: 9, year: year, cal: cal))

        // Columbus Day — 2nd Monday of October
        results.append(nthWeekday(.monday, n: 2, month: 10, year: year, cal: cal))

        // Veterans Day — Nov 11
        results.append(observed(month: 11, day: 11, year: year, cal: cal))

        // Thanksgiving — 4th Thursday of November
        results.append(nthWeekday(.thursday, n: 4, month: 11, year: year, cal: cal))

        // Christmas Day — Dec 25
        results.append(observed(month: 12, day: 25, year: year, cal: cal))

        return results.compactMap { $0 }
    }

    // MARK: - Private helpers

    /// Fixed-date holiday adjusted to the observed weekday.
    private static func observed(month: Int, day: Int, year: Int, cal: Calendar) -> Date {
        var comps = DateComponents(year: year, month: month, day: day)
        guard let date = cal.date(from: comps) else { return Date.distantPast }
        let weekday = cal.component(.weekday, from: date) // 1=Sun … 7=Sat
        if weekday == 7 { // Saturday → Friday
            return cal.date(byAdding: .day, value: -1, to: date) ?? date
        } else if weekday == 1 { // Sunday → Monday
            return cal.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }

    /// Nth occurrence of a weekday within a month (1-based).
    private static func nthWeekday(_ weekday: Weekday, n: Int, month: Int, year: Int, cal: Calendar) -> Date {
        var comps = DateComponents(year: year, month: month, day: 1)
        guard let firstOfMonth = cal.date(from: comps) else { return Date.distantPast }
        let targetCalWD = weekday.calWeekday // 1=Sun … 7=Sat
        let firstWD = cal.component(.weekday, from: firstOfMonth)
        var offset = targetCalWD - firstWD
        if offset < 0 { offset += 7 }
        offset += (n - 1) * 7
        return cal.date(byAdding: .day, value: offset, to: firstOfMonth) ?? firstOfMonth
    }

    /// Last occurrence of a weekday within a month.
    private static func lastWeekday(_ weekday: Weekday, month: Int, year: Int, cal: Calendar) -> Date {
        // Find the 1st of next month, go back 1 day = last day of target month, then find the weekday
        var comps = DateComponents(year: year, month: month + 1, day: 1)
        if month == 12 { comps = DateComponents(year: year + 1, month: 1, day: 1) }
        guard let firstOfNext = cal.date(from: comps),
              let lastOfMonth = cal.date(byAdding: .day, value: -1, to: firstOfNext) else {
            return Date.distantPast
        }
        let targetCalWD = weekday.calWeekday
        let lastWD = cal.component(.weekday, from: lastOfMonth)
        var offset = targetCalWD - lastWD
        if offset > 0 { offset -= 7 }
        return cal.date(byAdding: .day, value: offset, to: lastOfMonth) ?? lastOfMonth
    }
}
