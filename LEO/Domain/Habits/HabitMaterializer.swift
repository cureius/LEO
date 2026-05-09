import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "habit-materializer")

/// Generates `HabitInstanceItem`s for a 14-day rolling window.
/// Idempotent: re-running with the same window for the same habit produces the same instances.
actor HabitMaterializer {
    static let windowDays = 14

    private let habitRepository: HabitRepository
    private let recurrenceEngine = RecurrenceEngine.shared

    init(habitRepository: HabitRepository) {
        self.habitRepository = habitRepository
    }

    // MARK: - Materialize a habit

    /// Generate instances for `habit` over the next `windowDays` days.
    /// Existing completed/skipped instances are preserved; only open ones are regenerated.
    func materialize(habit: Habit) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date.now)
        let windowEnd = cal.date(byAdding: .day, value: Self.windowDays, to: today) ?? today.addingTimeInterval(86400 * Double(Self.windowDays))
        let window = DateInterval(start: today, end: windowEnd)

        // Parse the recurrence rule
        guard let rule = try? habit.recurrenceRule.parsed() else {
            logger.warning("Failed to parse rule for habit \(habit.id)")
            return
        }

        let occurrences: [Date]
        do {
            occurrences = try await recurrenceEngine.occurrences(
                rule: rule,
                anchorStart: habit.createdAt,
                in: window,
                extensions: habit.recurrenceRule.extensions
            )
        } catch {
            logger.error("Recurrence expansion failed for habit \(habit.id): \(error)")
            return
        }

        // Load existing instances
        let existing = await habitRepository.instances(for: habit.id, in: window)
        let existingByDate: [Date: HabitInstanceItem] = Dictionary(
            uniqueKeysWithValues: existing.compactMap { instance -> (Date, HabitInstanceItem)? in
                guard let d = instance.anchor.sortDate else { return nil }
                return (cal.startOfDay(for: d), instance)
            }
        )

        var toAdd: [HabitInstanceItem] = []
        for date in occurrences {
            let dayKey = cal.startOfDay(for: date)
            // Skip if we already have a completed/skipped instance for this day
            if let existing = existingByDate[dayKey], existing.completion != .open { continue }
            // Skip if we already have an open instance for this day (idempotent)
            if existingByDate[dayKey] != nil { continue }

            let anchor = anchorDate(for: habit, on: date, cal: cal)
            toAdd.append(HabitInstanceItem(
                title: habit.name,
                anchor: anchor,
                habitID: habit.id,
                targetDuration: habit.targetDuration
            ))
        }

        for instance in toAdd {
            try? await habitRepository.addInstance(instance)
        }

        if !toAdd.isEmpty {
            logger.info("Materialized \(toAdd.count) instances for habit '\(habit.name)'")
        }
    }

    // MARK: - Advance window (call at midnight)

    func advanceWindow() async {
        let habits = await habitRepository.allActive()
        for habit in habits {
            await materialize(habit: habit)
        }
        logger.info("Advanced materialization window for \(habits.count) habits")
    }

    // MARK: - Private helpers

    private func anchorDate(for habit: Habit, on date: Date, cal: Calendar) -> Anchor {
        let hint = habit.timeHint ?? .morning
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = hint.hintHour
        comps.minute = 0
        comps.second = 0
        guard let anchorDate = cal.date(from: comps) else { return .point(date) }

        if let duration = habit.targetDuration {
            let endDate = anchorDate.addingTimeInterval(duration.totalSeconds)
            return .timeBlock(start: anchorDate, end: endDate)
        }
        return .point(anchorDate)
    }
}

// MARK: - Duration seconds helper

extension Duration {
    var totalSeconds: Double {
        let (secs, attos) = self.components
        return Double(secs) + Double(attos) * 1e-18
    }
}
