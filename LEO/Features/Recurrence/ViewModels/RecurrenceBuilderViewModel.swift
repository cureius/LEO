import Foundation
import Observation

@Observable
final class RecurrenceBuilderViewModel {
    // MARK: - Core rule fields
    var frequency: RRuleFrequency = .weekly
    var interval: Int = 1
    var selectedWeekdays: Set<Weekday> = []
    var byMonthDay: [Int] = []
    var bySetPos: [Int] = []
    var byMonth: [Int] = []
    var weekStart: Weekday = .monday

    // MARK: - End condition
    enum EndCondition { case never, afterCount, onDate }
    var endCondition: EndCondition = .never
    var count: Int = 10
    var until: Date = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now

    // MARK: - LEO extensions
    var extensionsEnabled: [LEORuleExtension: Bool] = Dictionary(
        uniqueKeysWithValues: LEORuleExtension.allCases.map { ($0, false) }
    )

    // MARK: - Natural-language input
    var nlInput: String = ""

    // MARK: - Anchor (for next-occurrence preview)
    var anchorStart: Date = .now

    // MARK: - Derived rule

    var rule: RRule {
        RRule(
            frequency: frequency,
            interval: max(1, interval),
            count: endCondition == .afterCount ? count : nil,
            until: endCondition == .onDate ? until : nil,
            byDay: selectedWeekdays.sorted { $0.isoWeekdayNumber < $1.isoWeekdayNumber }
                .map { WeekdayOccurrence(weekday: $0) },
            byMonthDay: byMonthDay,
            byMonth: byMonth,
            bySetPos: bySetPos,
            weekStart: weekStart
        )
    }

    var activeExtensions: [LEORuleExtension] {
        LEORuleExtension.allCases.filter { extensionsEnabled[$0] == true }
    }

    var summaryText: String {
        RecurrenceFormatter.summary(for: rule)
    }

    // MARK: - Next 5 occurrences preview (updated async from the view)

    var nextOccurrences: [Date] = []

    func refreshOccurrences() async {
        let window = DateInterval(start: anchorStart, duration: 365 * 86400)
        let capturedRule = rule
        let capturedExtensions = activeExtensions
        let capturedAnchor = anchorStart
        let results = (try? await RecurrenceEngine.shared.occurrences(
            rule: capturedRule,
            anchorStart: capturedAnchor,
            in: window,
            extensions: capturedExtensions
        )) ?? []
        nextOccurrences = Array(results.prefix(5))
    }

    // MARK: - NL parse

    func applyNLInput() {
        guard !nlInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // Attempt to parse the input; fall back to no change on error
        if let parsed = try? RRule.parse(nlInput) {
            apply(parsed)
        }
    }

    // MARK: - Populate from an existing rule

    func apply(_ ruleIn: RRule) {
        frequency = ruleIn.frequency
        interval = ruleIn.interval
        selectedWeekdays = Set(ruleIn.byDay.map(\.weekday))
        byMonthDay = ruleIn.byMonthDay
        bySetPos = ruleIn.bySetPos
        byMonth = ruleIn.byMonth
        weekStart = ruleIn.weekStart

        if let n = ruleIn.count {
            endCondition = .afterCount; count = n
        } else if let d = ruleIn.until {
            endCondition = .onDate; until = d
        } else {
            endCondition = .never
        }

        nlInput = ruleIn.rfc5545
    }

    // MARK: - RecurrenceRule output

    var recurrenceRule: RecurrenceRule {
        RecurrenceRule(rule)
    }
}
