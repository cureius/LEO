import Foundation

/// Expands an RRule + anchor date into concrete occurrence dates within a window.
/// All date math uses the caller's Calendar (defaults to `.current`).
/// DST rule: weekly/daily recurrences preserve wall-clock time across spring-forward/fall-back.
public actor RecurrenceEngine {
    public static let shared = RecurrenceEngine()

    // Simple LRU cache: (cacheKey) → [Date]
    private var cache: [(key: CacheKey, value: [Date])] = []
    private let cacheCapacity = 50

    public init() {}

    // MARK: - Public API

    /// All occurrence dates for `rule` starting at `anchorStart` within `window`.
    /// - Parameter extensions: LEO-specific post-filters (workdays, holidays, etc.)
    /// - Throws: `RecurrenceError.windowTooLarge` if window > 5 years.
    public func occurrences(
        rule: RRule,
        anchorStart: Date,
        in window: DateInterval,
        extensions: [LEORuleExtension] = [],
        calendar: Calendar = .current
    ) throws -> [Date] {
        guard window.duration <= 5 * 365.25 * 86400 else {
            throw RecurrenceError.windowTooLarge
        }
        let key = CacheKey(rule: rule, anchor: anchorStart, window: window,
                           extensions: extensions, calendarID: "\(calendar.identifier)",
                           timeZone: calendar.timeZone.identifier)
        if let cached = cacheGet(key) { return cached }

        var dates = expand(rule: rule, anchorStart: anchorStart, in: window, cal: calendar)
        dates = applyExtensions(dates, extensions: extensions, calendar: calendar)
        dates = dates.sorted()
        cacheSet(key, value: dates)
        return dates
    }

    /// Next single occurrence after `after`.
    public func nextOccurrence(
        rule: RRule,
        after: Date,
        anchorStart: Date,
        extensions: [LEORuleExtension] = [],
        calendar: Calendar = .current
    ) throws -> Date? {
        let window = DateInterval(start: after, duration: 366 * 86400)
        let all = try occurrences(rule: rule, anchorStart: anchorStart, in: window,
                                  extensions: extensions, calendar: calendar)
        return all.first(where: { $0 > after })
    }

    // MARK: - Core expansion

    private func expand(rule: RRule, anchorStart: Date, in window: DateInterval, cal: Calendar) -> [Date] {
        switch rule.frequency {
        case .daily:   return expandDaily(rule: rule, anchorStart: anchorStart, in: window, cal: cal)
        case .weekly:  return expandWeekly(rule: rule, anchorStart: anchorStart, in: window, cal: cal)
        case .monthly: return expandMonthly(rule: rule, anchorStart: anchorStart, in: window, cal: cal)
        case .yearly:  return expandYearly(rule: rule, anchorStart: anchorStart, in: window, cal: cal)
        }
    }

    // MARK: Daily

    private func expandDaily(rule: RRule, anchorStart: Date, in window: DateInterval, cal: Calendar) -> [Date] {
        var results: [Date] = []
        var current = floorToDay(anchorStart, cal: cal)
        // Advance to window start if anchor is before
        while current < window.start {
            guard let next = cal.date(byAdding: .day, value: rule.interval, to: current) else { break }
            current = next
        }
        var count = 0
        while current <= window.end {
            let candidate = preserveTime(anchorStart, onDay: current, cal: cal)
            if candidate >= window.start && candidate <= window.end {
                results.append(candidate)
                count += 1
                if let maxCount = rule.count, count >= maxCount { break }
                if let until = rule.until, candidate >= until { break }
            }
            guard let next = cal.date(byAdding: .day, value: rule.interval, to: current) else { break }
            current = next
        }
        return results
    }

    // MARK: Weekly

    private func expandWeekly(rule: RRule, anchorStart: Date, in window: DateInterval, cal: Calendar) -> [Date] {
        var results: [Date] = []
        let targetWeekdays: [Weekday]
        if rule.byDay.isEmpty {
            // Default: same weekday as anchor
            targetWeekdays = [calWeekdayToLEO(cal.component(.weekday, from: anchorStart))]
        } else {
            targetWeekdays = rule.byDay.map(\.weekday)
        }
        // Find the Monday of the anchor's week, then walk week-by-week
        var weekStart = startOfWeek(anchorStart, weekStart: rule.weekStart, cal: cal)
        let windowStartWeek = startOfWeek(window.start, weekStart: rule.weekStart, cal: cal)
        // Rewind to the correct interval boundary
        weekStart = alignToInterval(weekStart, windowStart: windowStartWeek, interval: rule.interval, unit: .weekOfYear, cal: cal)

        var count = 0
        while weekStart <= window.end {
            for wd in targetWeekdays.sorted(by: { $0.isoWeekdayNumber < $1.isoWeekdayNumber }) {
                guard let day = cal.date(bySetting: .weekday, value: wd.calWeekday, of: weekStart) else { continue }
                // Adjust if the computed day is before week start
                let candidate = preserveTime(anchorStart, onDay: day, cal: cal)
                guard candidate >= window.start, candidate <= window.end else { continue }
                guard candidate >= anchorStart || cal.isDate(candidate, inSameDayAs: anchorStart) else { continue }
                if let until = rule.until, candidate > until { continue }
                results.append(candidate)
                count += 1
                if let maxCount = rule.count, count >= maxCount { return results }
            }
            guard let next = cal.date(byAdding: .weekOfYear, value: rule.interval, to: weekStart) else { break }
            weekStart = next
        }
        return results
    }

    // MARK: Monthly

    private func expandMonthly(rule: RRule, anchorStart: Date, in window: DateInterval, cal: Calendar) -> [Date] {
        var results: [Date] = []
        var monthStart = cal.date(from: cal.dateComponents([.year, .month], from: anchorStart))!
        let windowMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: window.start))!
        monthStart = alignToInterval(monthStart, windowStart: windowMonthStart, interval: rule.interval, unit: .month, cal: cal)

        var count = 0
        while monthStart <= window.end {
            var candidates: [Date] = []

            if !rule.byMonthDay.isEmpty {
                for day in rule.byMonthDay {
                    if let d = cal.date(bySetting: .day, value: day, of: monthStart) {
                        candidates.append(d)
                    }
                }
            } else if !rule.byDay.isEmpty {
                candidates = byDayCandidates(for: rule.byDay, inMonth: monthStart, cal: cal)
            } else {
                // Same day-of-month as anchor (clamped to month end)
                let dom = cal.component(.day, from: anchorStart)
                if let d = cal.date(bySetting: .day, value: dom, of: monthStart) {
                    candidates = [d]
                }
            }

            if !rule.bySetPos.isEmpty {
                candidates = applyBySetPos(rule.bySetPos, to: candidates.sorted())
            }

            for day in candidates.sorted() {
                let candidate = preserveTime(anchorStart, onDay: day, cal: cal)
                guard candidate >= window.start, candidate <= window.end else { continue }
                guard candidate >= anchorStart || cal.isDate(candidate, inSameDayAs: anchorStart) else { continue }
                if let until = rule.until, candidate > until { continue }
                results.append(candidate)
                count += 1
                if let maxCount = rule.count, count >= maxCount { return results }
            }

            guard let next = cal.date(byAdding: .month, value: rule.interval, to: monthStart) else { break }
            monthStart = next
        }
        return results
    }

    // MARK: Yearly

    private func expandYearly(rule: RRule, anchorStart: Date, in window: DateInterval, cal: Calendar) -> [Date] {
        var results: [Date] = []
        var yearStart = cal.date(from: cal.dateComponents([.year], from: anchorStart))!
        let windowYearStart = cal.date(from: cal.dateComponents([.year], from: window.start))!
        yearStart = alignToInterval(yearStart, windowStart: windowYearStart, interval: rule.interval, unit: .year, cal: cal)

        var count = 0
        while yearStart <= window.end {
            var candidates: [Date] = []
            if !rule.byMonth.isEmpty {
                for m in rule.byMonth {
                    if let monthDate = cal.date(bySetting: .month, value: m, of: yearStart) {
                        if !rule.byDay.isEmpty {
                            candidates += byDayCandidates(for: rule.byDay, inMonth: monthDate, cal: cal)
                        } else {
                            let dom = cal.component(.day, from: anchorStart)
                            if let d = cal.date(bySetting: .day, value: dom, of: monthDate) {
                                candidates.append(d)
                            }
                        }
                    }
                }
            } else {
                candidates = [anchorStart]
                if let d = cal.date(bySetting: .year, value: cal.component(.year, from: yearStart), of: anchorStart) {
                    candidates = [d]
                }
            }

            for day in candidates.sorted() {
                let candidate = preserveTime(anchorStart, onDay: day, cal: cal)
                guard candidate >= window.start, candidate <= window.end else { continue }
                guard candidate >= anchorStart || cal.isDate(candidate, inSameDayAs: anchorStart) else { continue }
                if let until = rule.until, candidate > until { continue }
                results.append(candidate)
                count += 1
                if let maxCount = rule.count, count >= maxCount { return results }
            }

            guard let next = cal.date(byAdding: .year, value: rule.interval, to: yearStart) else { break }
            yearStart = next
        }
        return results
    }

    // MARK: - Helpers

    /// Collect all dates in a month matching BYDAY entries (with optional ordinal).
    private func byDayCandidates(for byDay: [WeekdayOccurrence], inMonth monthStart: Date, cal: Calendar) -> [Date] {
        var results: [Date] = []
        let range = cal.range(of: .day, in: .month, for: monthStart) ?? (1..<32)
        var allInMonth: [Date] = []
        for day in range {
            if let d = cal.date(bySetting: .day, value: day, of: monthStart) { allInMonth.append(d) }
        }
        for wo in byDay {
            let matching = allInMonth.filter { calWeekdayToLEO(cal.component(.weekday, from: $0)) == wo.weekday }
            if let ord = wo.ordinal {
                let idx = ord > 0 ? ord - 1 : matching.count + ord
                if idx >= 0 && idx < matching.count { results.append(matching[idx]) }
            } else {
                results += matching
            }
        }
        return results
    }

    private func applyBySetPos(_ positions: [Int], to sorted: [Date]) -> [Date] {
        guard !sorted.isEmpty else { return [] }
        return positions.compactMap { pos -> Date? in
            let idx = pos > 0 ? pos - 1 : sorted.count + pos
            guard idx >= 0, idx < sorted.count else { return nil }
            return sorted[idx]
        }
    }

    /// Preserve the wall-clock time of `anchorStart` on a different calendar day.
    private func preserveTime(_ source: Date, onDay day: Date, cal: Calendar) -> Date {
        var comps = cal.dateComponents([.hour, .minute, .second], from: source)
        let dayComps = cal.dateComponents([.year, .month, .day], from: day)
        comps.year = dayComps.year; comps.month = dayComps.month; comps.day = dayComps.day
        return cal.date(from: comps) ?? day
    }

    private func floorToDay(_ date: Date, cal: Calendar) -> Date {
        cal.startOfDay(for: date)
    }

    private func startOfWeek(_ date: Date, weekStart: Weekday, cal: Calendar) -> Date {
        var c = cal
        c.firstWeekday = weekStart.calWeekday
        return c.date(from: c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
    }

    private func alignToInterval(_ anchor: Date, windowStart: Date, interval: Int, unit: Calendar.Component, cal: Calendar) -> Date {
        guard interval > 1, anchor < windowStart else { return anchor }
        var current = anchor
        while let next = cal.date(byAdding: unit, value: interval, to: current), next <= windowStart {
            current = next
        }
        return current
    }

    private func calWeekdayToLEO(_ weekday: Int) -> Weekday {
        // Calendar.weekday: 1=Sun, 2=Mon … 7=Sat
        switch weekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }

    // MARK: - Extensions

    private func applyExtensions(_ dates: [Date], extensions: [LEORuleExtension], calendar: Calendar) -> [Date] {
        var result = dates
        for ext in extensions {
            switch ext {
            case .workdaysOnly:
                result = result.filter { !isWeekend($0, cal: calendar) }
            case .skipUSHolidays:
                result = result.filter { !USFederalHolidays.isHoliday($0, cal: calendar) }
            case .firstWeekdayOfMonth:
                result = result.map { firstWeekdayIfNeeded($0, cal: calendar) }
            }
        }
        return result
    }

    private func isWeekend(_ date: Date, cal: Calendar) -> Bool {
        let wd = cal.component(.weekday, from: date)
        return wd == 1 || wd == 7
    }

    private func firstWeekdayIfNeeded(_ date: Date, cal: Calendar) -> Date {
        var d = date
        while isWeekend(d, cal: cal) || USFederalHolidays.isHoliday(d, cal: cal) {
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return d
    }

    // MARK: - Cache

    private struct CacheKey: Hashable {
        let rule: RRule
        let anchor: Date
        let window: DateInterval
        let extensions: [LEORuleExtension]
        let calendarID: String
        let timeZone: String
    }

    private func cacheGet(_ key: CacheKey) -> [Date]? {
        cache.first(where: { $0.key == key })?.value
    }

    private func cacheSet(_ key: CacheKey, value: [Date]) {
        if cache.count >= cacheCapacity { cache.removeFirst() }
        cache.append((key, value))
    }
}

// MARK: - Error

public enum RecurrenceError: Error, Sendable {
    case windowTooLarge  // > 5 years requested
}

// MARK: - Weekday helpers

extension Weekday {
    /// ISO weekday number (Mon=1 … Sun=7)
    var isoWeekdayNumber: Int {
        switch self {
        case .monday: return 1; case .tuesday: return 2; case .wednesday: return 3
        case .thursday: return 4; case .friday: return 5; case .saturday: return 6
        case .sunday: return 7
        }
    }

    /// Calendar.weekday (Sun=1 … Sat=7)
    var calWeekday: Int {
        switch self {
        case .sunday: return 1; case .monday: return 2; case .tuesday: return 3
        case .wednesday: return 4; case .thursday: return 5; case .friday: return 6
        case .saturday: return 7
        }
    }
}
