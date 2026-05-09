import Foundation

// MARK: - Streak state

public struct StreakState: Equatable, Sendable {
    /// Current active streak in days (counting completed days).
    public let activeStreakDays: Int
    /// All-time longest streak.
    public let longestStreak: Int
    /// How many misses remain this week before streak breaks (nil if forgiveness is .none).
    public let forgivenessRemainingThisPeriod: Int?
    /// True if one more miss would break the streak.
    public let atRisk: Bool

    public static let zero = StreakState(
        activeStreakDays: 0, longestStreak: 0,
        forgivenessRemainingThisPeriod: nil, atRisk: false
    )
}

// MARK: - StreakEngine

/// Pure-functional streak computation. No side effects, no repository calls.
public enum StreakEngine {

    public static func currentStreak(
        for habit: Habit,
        instances: [HabitInstanceItem],
        calendar: Calendar = .current
    ) -> StreakState {
        guard !instances.isEmpty else { return .zero }

        let sorted = instances
            .filter { $0.anchor.sortDate != nil }
            .sorted { ($0.anchor.sortDate!) < ($1.anchor.sortDate!) }

        // Group instances by calendar day
        let byDay = Dictionary(grouping: sorted) { instance -> Date in
            calendar.startOfDay(for: instance.anchor.sortDate!)
        }

        let today = calendar.startOfDay(for: Date.now)

        // Walk back from today computing streak
        var activeStreak = 0
        var longestStreak = 0
        var tempStreak = 0
        var cursor = today

        // Count misses this ISO week for forgiveness tracking
        let weekMisses = missesThisWeek(byDay: byDay, today: today, calendar: calendar)

        while cursor >= (sorted.first?.anchor.sortDate.map { calendar.startOfDay(for: $0) } ?? cursor) {
            let dayInstances = byDay[cursor] ?? []
            let hasCompletion = dayInstances.contains { $0.completion.isFinished }

            if hasCompletion {
                tempStreak += 1
            } else if cursor < today {
                // A miss — check if it falls within forgiveness
                if forgiven(miss: cursor, byDay: byDay, forgiveness: habit.forgiveness, calendar: calendar) {
                    tempStreak += 1  // Forgiven miss: streak continues
                } else {
                    longestStreak = max(longestStreak, tempStreak)
                    break  // Streak broken
                }
            }

            if cursor == today { activeStreak = tempStreak }
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor.addingTimeInterval(-86400)
            if cursor == cursor.addingTimeInterval(-86400) { break }  // Failsafe
        }

        longestStreak = max(longestStreak, tempStreak)

        // Forgiveness remaining this week
        let forgivenessRemaining: Int?
        switch habit.forgiveness {
        case .none:
            forgivenessRemaining = nil
        case .misses(let perWeek):
            forgivenessRemaining = max(0, perWeek - weekMisses)
        case .percent:
            forgivenessRemaining = nil  // Percent-based doesn't have a simple "remaining" count
        }

        // atRisk: streak > 0, today not yet completed, and forgiveness is running out
        let todayCompleted = byDay[today]?.contains { $0.completion.isFinished } ?? false
        let atRisk = activeStreak > 0 && !todayCompleted && (forgivenessRemaining == 0)

        return StreakState(
            activeStreakDays: activeStreak,
            longestStreak: longestStreak,
            forgivenessRemainingThisPeriod: forgivenessRemaining,
            atRisk: atRisk
        )
    }

    // MARK: - Private helpers

    private static func missesThisWeek(
        byDay: [Date: [HabitInstanceItem]],
        today: Date,
        calendar: Calendar
    ) -> Int {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else { return 0 }
        var misses = 0
        var day = weekInterval.start
        while day <= min(today.addingTimeInterval(-86400), weekInterval.end) {
            let dayInstances = byDay[day] ?? []
            if !dayInstances.isEmpty && !dayInstances.contains(where: { $0.completion.isFinished }) {
                misses += 1
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
        }
        return misses
    }

    private static func forgiven(
        miss: Date,
        byDay: [Date: [HabitInstanceItem]],
        forgiveness: HabitForgiveness,
        calendar: Calendar
    ) -> Bool {
        switch forgiveness {
        case .none:
            return false

        case .misses(let perWeek):
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: miss) else { return false }
            var weekMisses = 0
            var day = weekInterval.start
            while day <= weekInterval.end {
                let dayInstances = byDay[day] ?? []
                let had = !dayInstances.isEmpty
                let completed = dayInstances.contains { $0.completion.isFinished }
                if had && !completed { weekMisses += 1 }
                if weekMisses > perWeek { return false }
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
            }
            return weekMisses <= perWeek

        case .percent(let minimum):
            // Check completion rate in trailing 14 days
            let windowStart = calendar.date(byAdding: .day, value: -13, to: miss) ?? miss
            let daysInWindow = byDay.keys.filter { $0 >= windowStart && $0 <= miss }
            guard !daysInWindow.isEmpty else { return true }
            let completedDays = daysInWindow.filter { day in
                byDay[day]?.contains { $0.completion.isFinished } ?? false
            }.count
            return Double(completedDays) / Double(daysInWindow.count) >= minimum
        }
    }
}
