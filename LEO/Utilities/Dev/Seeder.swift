import Foundation

/// Produces realistic fixture data covering all item types, time ranges, and habit histories.
#if DEBUG
struct Seeder {

    // MARK: - Entry point

    func seedAll(itemRepository: ItemRepository, habitRepository: HabitRepository) async throws {
        let tags = makeTags()

        for item in makePastItems(tags: tags)   { try await itemRepository.add(item) }
        for item in makeTodayItems(tags: tags)  { try await itemRepository.add(item) }
        for item in makeFutureItems(tags: tags) { try await itemRepository.add(item) }

        let habits = makeHabits()
        for habit in habits { try await habitRepository.add(habit) }
        for instance in makeHabitInstances(habits: habits) {
            try await habitRepository.addInstance(instance)
        }
    }

    // MARK: - Tags

    private func makeTags() -> [String: Tag] {
        [
            "work":     Tag(name: "Work",     color: .blue),
            "personal": Tag(name: "Personal", color: .green),
            "health":   Tag(name: "Health",   color: .red),
            "finance":  Tag(name: "Finance",  color: .yellow),
            "travel":   Tag(name: "Travel",   color: .teal),
        ]
    }

    // MARK: - Helpers

    private func time(_ h: Int, _ m: Int = 0, relativeTo base: Date, offsetDays: Int = 0) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: offsetDays, to: base)!
        return cal.date(bySettingHour: h, minute: m, second: 0, of: day)!
    }

    private func done(at date: Date, jitter: Double = 180) -> Completion {
        .completed(at: date.addingTimeInterval(Double.random(in: 30...jitter)))
    }

    // MARK: - Today's full schedule

    private func makeTodayItems(tags: [String: Tag]) -> [any Item] {
        let base = Calendar.current.startOfDay(for: .now)
        func t(_ h: Int, _ m: Int = 0) -> Date { time(h, m, relativeTo: base) }

        return [
            // 6:30am — Wake-up alarm (already fired)
            AlarmItem(
                title: "Wake up",
                anchor: .point(t(6, 30)),
                completion: .completed(at: t(6, 31)),
                soundProfile: .gentle,
                escalates: true
            ),

            // 9:00–9:30am — Team standup
            EventItem(
                title: "Team standup",
                notes: "Sprint day 3 — blockers & progress",
                anchor: .timeBlock(start: t(9), end: t(9, 30)),
                tags: [tags["work"]!],
                attendees: ["Alex Chen", "Priya Menon", "Sam Okafor"]
            ),

            // 10:00am–12:00pm — Deep work block
            EventItem(
                title: "Deep work — Auth refactor",
                notes: "No interruptions. Focus on OAuth token refresh flow.",
                importance: .high,
                anchor: .timeBlock(start: t(10), end: t(12)),
                tags: [tags["work"]!]
            ),

            // 12:00–12:45pm — Lunch with a friend
            EventItem(
                title: "Lunch with Sarah",
                anchor: .timeBlock(start: t(12), end: t(12, 45)),
                tags: [tags["personal"]!],
                location: "The Fig Tree Café, 12 Park Lane",
                attendees: ["Sarah Kim"]
            ),

            // 12:30pm — Take medication (completed)
            ReminderItem(
                title: "Take medication",
                anchor: .point(t(12, 30)),
                completion: .completed(at: t(12, 32)),
                tags: [tags["health"]!]
            ),

            // 2:00–3:00pm — Product review
            EventItem(
                title: "Product review — v2.1 scope",
                importance: .high,
                anchor: .timeBlock(start: t(14), end: t(15)),
                tags: [tags["work"]!],
                attendees: ["Jordan Park", "Alex Chen", "Ming Liu"]
            ),

            // 3:00pm — Reminder
            ReminderItem(
                title: "Pick up prescription from pharmacy",
                anchor: .point(t(15)),
                tags: [tags["health"]!]
            ),

            // 4:30–5:30pm — 1:1 with manager
            EventItem(
                title: "1:1 with Jordan",
                notes: "Q3 goals check-in + role expansion discussion",
                anchor: .timeBlock(start: t(16, 30), end: t(17, 30)),
                tags: [tags["work"]!],
                attendees: ["Jordan Park"]
            ),

            // 8:00pm — Call dad
            ReminderItem(
                title: "Call dad",
                anchor: .point(t(20)),
                tags: [tags["personal"]!]
            ),

            // Untimed tasks
            TaskItem(
                title: "Review PR #207 — payment gateway",
                importance: .high,
                anchor: .untimed,
                tags: [tags["work"]!]
            ),
            TaskItem(
                title: "Reply to client proposal email",
                importance: .urgent,
                anchor: .untimed,
                tags: [tags["work"]!]
            ),
            TaskItem(
                title: "Book dentist appointment",
                anchor: .untimed,
                tags: [tags["health"]!]
            ),
            TaskItem(
                title: "Order birthday gift for dad",
                anchor: .untimed,
                tags: [tags["personal"]!]
            ),
        ]
    }

    // MARK: - Past items (yesterday → 2 weeks ago)

    private func makePastItems(tags: [String: Tag]) -> [any Item] {
        let base = Calendar.current.startOfDay(for: .now)
        func t(_ h: Int, _ m: Int = 0, ago days: Int) -> Date { time(h, m, relativeTo: base, offsetDays: -days) }

        return [
            // ── Yesterday ────────────────────────────────────────────────
            EventItem(
                title: "Team standup",
                anchor: .timeBlock(start: t(9, 0, ago: 1), end: t(9, 30, ago: 1)),
                completion: done(at: t(9, 30, ago: 1)),
                tags: [tags["work"]!],
                attendees: ["Alex Chen", "Priya Menon", "Sam Okafor"]
            ),
            EventItem(
                title: "Design system review",
                anchor: .timeBlock(start: t(14, 0, ago: 1), end: t(15, 0, ago: 1)),
                completion: done(at: t(15, 0, ago: 1)),
                tags: [tags["work"]!]
            ),
            TaskItem(
                title: "Buy groceries",
                anchor: .dueAt(t(18, 0, ago: 1)),
                completion: done(at: t(17, 45, ago: 1)),
                tags: [tags["personal"]!]
            ),
            ReminderItem(
                title: "Call insurance about claim",
                anchor: .point(t(11, 0, ago: 1)),
                completion: done(at: t(11, 5, ago: 1))
            ),
            // Overdue open task — still pending
            TaskItem(
                title: "Submit expense report",
                importance: .urgent,
                anchor: .dueAt(t(17, 0, ago: 1)),
                tags: [tags["finance"]!]
            ),

            // ── 2 days ago ───────────────────────────────────────────────
            EventItem(
                title: "Date night",
                anchor: .timeBlock(start: t(19, 0, ago: 2), end: t(22, 0, ago: 2)),
                completion: done(at: t(22, 0, ago: 2)),
                tags: [tags["personal"]!],
                location: "Osteria Marco, Downtown"
            ),
            TaskItem(
                title: "Pay utility bills",
                anchor: .dueAt(t(12, 0, ago: 2)),
                completion: done(at: t(11, 30, ago: 2)),
                tags: [tags["finance"]!]
            ),

            // ── 3 days ago ───────────────────────────────────────────────
            EventItem(
                title: "Dentist — routine checkup",
                anchor: .timeBlock(start: t(10, 0, ago: 3), end: t(11, 0, ago: 3)),
                completion: done(at: t(11, 0, ago: 3)),
                tags: [tags["health"]!],
                location: "Bright Smile Dental, Suite 4B"
            ),
            ReminderItem(
                title: "Renew gym membership",
                anchor: .point(t(9, 0, ago: 3)),
                completion: done(at: t(9, 10, ago: 3)),
                tags: [tags["health"]!]
            ),

            // ── 5 days ago ───────────────────────────────────────────────
            EventItem(
                title: "Sprint planning — Sprint 22",
                notes: "Velocity target: 38 points",
                anchor: .timeBlock(start: t(10, 0, ago: 5), end: t(12, 0, ago: 5)),
                completion: done(at: t(12, 0, ago: 5)),
                tags: [tags["work"]!],
                attendees: ["Alex Chen", "Priya Menon", "Sam Okafor", "Jordan Park"]
            ),
            TaskItem(
                title: "Write sprint retrospective notes",
                anchor: .dueAt(t(17, 0, ago: 5)),
                completion: done(at: t(16, 30, ago: 5)),
                tags: [tags["work"]!]
            ),

            // ── Last Friday — weekly review ───────────────────────────────
            EventItem(
                title: "Weekly review",
                notes: "Processed inbox, updated projects, planned next week",
                anchor: .timeBlock(start: t(16, 0, ago: 7), end: t(17, 30, ago: 7)),
                completion: done(at: t(17, 28, ago: 7)),
                tags: [tags["work"]!]
            ),

            // ── 10 days ago ──────────────────────────────────────────────
            EventItem(
                title: "Quarterly business review",
                importance: .high,
                anchor: .timeBlock(start: t(9, 0, ago: 10), end: t(12, 0, ago: 10)),
                completion: done(at: t(12, 0, ago: 10)),
                tags: [tags["work"]!],
                attendees: ["Jordan Park", "CEO", "CFO"]
            ),
            AlarmItem(
                title: "Early start — QBR prep",
                anchor: .point(t(5, 45, ago: 10)),
                completion: done(at: t(5, 46, ago: 10))
            ),
        ]
    }

    // MARK: - Future items (+1 → +14 days)

    private func makeFutureItems(tags: [String: Tag]) -> [any Item] {
        let base = Calendar.current.startOfDay(for: .now)
        func t(_ h: Int, _ m: Int = 0, ahead days: Int) -> Date { time(h, m, relativeTo: base, offsetDays: days) }

        return [
            // ── Tomorrow ─────────────────────────────────────────────────
            AlarmItem(
                title: "Early morning — conference call prep",
                anchor: .point(t(6, 0, ahead: 1)),
                soundProfile: .gentle
            ),
            EventItem(
                title: "London HQ call",
                notes: "Timezone: GMT+1. Dial-in code: 8821-44",
                importance: .high,
                anchor: .timeBlock(start: t(8, 0, ahead: 1), end: t(9, 0, ahead: 1)),
                tags: [tags["work"]!],
                attendees: ["Rebecca Walsh", "Tom Briggs"]
            ),
            TaskItem(
                title: "Send Q3 board report",
                importance: .high,
                anchor: .dueAt(t(12, 0, ahead: 1)),
                tags: [tags["work"]!],
                estimatedDuration: .seconds(5400)
            ),

            // ── +2 days ──────────────────────────────────────────────────
            TaskItem(
                title: "Book hotel for NYC trip",
                anchor: .dueAt(t(18, 0, ahead: 2)),
                tags: [tags["travel"]!]
            ),
            EventItem(
                title: "Team happy hour",
                anchor: .timeBlock(start: t(17, 30, ahead: 2), end: t(19, 30, ahead: 2)),
                tags: [tags["personal"]!, tags["work"]!],
                location: "The Rooftop Bar, 5th & Main"
            ),

            // ── +3 days ──────────────────────────────────────────────────
            EventItem(
                title: "Doctor — annual physical",
                importance: .high,
                anchor: .timeBlock(start: t(11, 0, ahead: 3), end: t(12, 0, ahead: 3)),
                tags: [tags["health"]!],
                location: "City Health Clinic, Dr. Patel"
            ),
            TaskItem(
                title: "Fast 12h before blood draw",
                anchor: .dueAt(t(23, 0, ahead: 2)),
                tags: [tags["health"]!]
            ),

            // ── +4 days ──────────────────────────────────────────────────
            TaskItem(
                title: "Pay rent",
                importance: .high,
                anchor: .dueAt(t(12, 0, ahead: 4)),
                tags: [tags["finance"]!]
            ),

            // ── +5 days ──────────────────────────────────────────────────
            EventItem(
                title: "Friend's housewarming",
                anchor: .timeBlock(start: t(18, 0, ahead: 5), end: t(21, 0, ahead: 5)),
                tags: [tags["personal"]!],
                location: "42 Maple St, Apt 8"
            ),
            TaskItem(
                title: "Buy housewarming gift",
                anchor: .dueAt(t(14, 0, ahead: 4)),
                tags: [tags["personal"]!]
            ),

            // ── +7 days — team offsite ───────────────────────────────────
            EventItem(
                title: "Team offsite — product strategy",
                notes: "Full day. Bring laptop + charger.",
                importance: .high,
                anchor: .timeBlock(start: t(9, 0, ahead: 7), end: t(17, 0, ahead: 7)),
                tags: [tags["work"]!],
                location: "Westside Conference Center, Room A"
            ),

            // ── +10–12 days — NYC trip ────────────────────────────────────
            AlarmItem(
                title: "Airport — flight to NYC",
                anchor: .point(t(5, 30, ahead: 10)),
                escalates: true
            ),
            EventItem(
                title: "Flight JFK → NYC (AA 2241)",
                anchor: .timeBlock(start: t(8, 0, ahead: 10), end: t(11, 30, ahead: 10)),
                tags: [tags["travel"]!],
                location: "JFK Terminal 8"
            ),
            EventItem(
                title: "NYC client kickoff meeting",
                importance: .high,
                anchor: .timeBlock(start: t(14, 0, ahead: 11), end: t(16, 30, ahead: 11)),
                tags: [tags["work"]!, tags["travel"]!],
                location: "Acme Corp, 400 Park Ave",
                attendees: ["Dana Torres", "Mike Reyes", "Alicia Fernandez"]
            ),
            EventItem(
                title: "Client dinner — Le Bernardin",
                anchor: .timeBlock(start: t(19, 0, ahead: 11), end: t(21, 30, ahead: 11)),
                tags: [tags["work"]!, tags["travel"]!],
                location: "Le Bernardin, 155 W 51st St"
            ),
            EventItem(
                title: "Return flight NYC → home (AA 1874)",
                anchor: .timeBlock(start: t(18, 0, ahead: 12), end: t(21, 45, ahead: 12)),
                tags: [tags["travel"]!],
                location: "JFK Terminal 8"
            ),

            // ── +14 days ─────────────────────────────────────────────────
            ReminderItem(
                title: "Dad's birthday — call first thing",
                importance: .high,
                anchor: .point(t(8, 0, ahead: 14)),
                tags: [tags["personal"]!]
            ),
        ]
    }

    // MARK: - Habits

    private func makeHabits() -> [Habit] {
        [
            Habit(
                name: "Morning run",
                frequency: .specificDays([.monday, .wednesday, .friday, .saturday]),
                timeHint: .morning,
                targetDuration: .seconds(2700),
                recurrenceRule: .weekly(on: [.monday, .wednesday, .friday, .saturday]),
                forgiveness: .misses(perWeek: 1),
                createdAt: .now.addingTimeInterval(-90 * 86400)
            ),
            Habit(
                name: "Meditation",
                frequency: .daily,
                timeHint: .morning,
                targetDuration: .seconds(1200),
                recurrenceRule: .daily(),
                forgiveness: .misses(perWeek: 1),
                createdAt: .now.addingTimeInterval(-90 * 86400)
            ),
            Habit(
                name: "Evening journal",
                frequency: .daily,
                timeHint: .evening,
                targetDuration: .seconds(900),
                recurrenceRule: .daily(),
                forgiveness: .misses(perWeek: 0),
                createdAt: .now.addingTimeInterval(-30 * 86400)
            ),
            Habit(
                name: "Gym (weights)",
                frequency: .specificDays([.tuesday, .thursday]),
                timeHint: .evening,
                targetDuration: .seconds(3600),
                recurrenceRule: .weekly(on: [.tuesday, .thursday]),
                forgiveness: .misses(perWeek: 1),
                createdAt: .now.addingTimeInterval(-60 * 86400)
            ),
        ]
    }

    // MARK: - Habit instances

    private func makeHabitInstances(habits: [Habit]) -> [HabitInstanceItem] {
        var instances: [HabitInstanceItem] = []
        let today = Calendar.current.startOfDay(for: .now)
        for habit in habits {
            switch habit.name {
            case "Morning run":    instances += runInstances(habit: habit, today: today)
            case "Meditation":     instances += meditationInstances(habit: habit, today: today)
            case "Evening journal": instances += journalInstances(habit: habit, today: today)
            case "Gym (weights)":  instances += gymInstances(habit: habit, today: today)
            default: break
            }
        }
        return instances
    }

    // Morning run — Mon/Wed/Fri/Sat, 90-day history, ~90% compliance, 18-day current streak
    private func runInstances(habit: Habit, today: Date) -> [HabitInstanceItem] {
        let cal = Calendar.current
        let targetWeekdays: Set<Int> = [2, 4, 6, 7] // Mon Wed Fri Sat
        let skippedDaysAgo: Set<Int> = [3, 17, 24, 31, 45, 52, 67, 73, 83]
        var result: [HabitInstanceItem] = []
        for daysOffset in stride(from: -90, through: 7, by: 1) {
            let day = cal.date(byAdding: .day, value: daysOffset, to: today)!
            guard targetWeekdays.contains(cal.component(.weekday, from: day)) else { continue }
            let start = cal.date(bySettingHour: 7, minute: 0, second: 0, of: day)!
            let end   = start.addingTimeInterval(2700)
            let daysAgo = -daysOffset
            let completion: Completion = daysOffset >= 0 ? .open
                : skippedDaysAgo.contains(daysAgo) ? .skipped(at: start, reason: "Rest day")
                : done(at: end)
            result.append(HabitInstanceItem(
                title: habit.name,
                anchor: .timeBlock(start: start, end: end),
                completion: completion,
                habitID: habit.id,
                targetDuration: habit.targetDuration
            ))
        }
        return result
    }

    // Meditation — daily, 90-day history, 3-day miss cluster ~3 weeks ago, 14-day streak
    private func meditationInstances(habit: Habit, today: Date) -> [HabitInstanceItem] {
        let cal = Calendar.current
        let skippedDaysAgo: Set<Int> = [22, 23, 24, 38, 55, 71]
        var result: [HabitInstanceItem] = []
        for daysOffset in stride(from: -90, through: 3, by: 1) {
            let day = cal.date(byAdding: .day, value: daysOffset, to: today)!
            let start = cal.date(bySettingHour: 8, minute: 0, second: 0, of: day)!
            let end   = start.addingTimeInterval(1200)
            let daysAgo = -daysOffset
            let completion: Completion = daysOffset >= 0 ? .open
                : skippedDaysAgo.contains(daysAgo) ? .skipped(at: start, reason: nil)
                : done(at: end)
            result.append(HabitInstanceItem(
                title: habit.name,
                anchor: .timeBlock(start: start, end: end),
                completion: completion,
                habitID: habit.id,
                targetDuration: habit.targetDuration
            ))
        }
        return result
    }

    // Evening journal — 30-day history, missed yesterday → "at risk" badge
    private func journalInstances(habit: Habit, today: Date) -> [HabitInstanceItem] {
        let cal = Calendar.current
        let skippedDaysAgo: Set<Int> = [1, 9, 18]
        var result: [HabitInstanceItem] = []
        for daysOffset in stride(from: -30, through: 0, by: 1) {
            let day = cal.date(byAdding: .day, value: daysOffset, to: today)!
            let start = cal.date(bySettingHour: 21, minute: 0, second: 0, of: day)!
            let end   = start.addingTimeInterval(900)
            let daysAgo = -daysOffset
            let completion: Completion = daysOffset == 0 ? .open
                : skippedDaysAgo.contains(daysAgo) ? .skipped(at: start, reason: nil)
                : done(at: end)
            result.append(HabitInstanceItem(
                title: habit.name,
                anchor: .timeBlock(start: start, end: end),
                completion: completion,
                habitID: habit.id,
                targetDuration: habit.targetDuration
            ))
        }
        return result
    }

    // Gym — Tue/Thu, 60-day history, missed last Thu, good recent streak
    private func gymInstances(habit: Habit, today: Date) -> [HabitInstanceItem] {
        let cal = Calendar.current
        let targetWeekdays: Set<Int> = [3, 5] // Tue Thu
        let skippedDaysAgo: Set<Int> = [2, 16, 30, 44]
        var result: [HabitInstanceItem] = []
        for daysOffset in stride(from: -60, through: 7, by: 1) {
            let day = cal.date(byAdding: .day, value: daysOffset, to: today)!
            guard targetWeekdays.contains(cal.component(.weekday, from: day)) else { continue }
            let start = cal.date(bySettingHour: 18, minute: 0, second: 0, of: day)!
            let end   = start.addingTimeInterval(3600)
            let daysAgo = -daysOffset
            let completion: Completion = daysOffset >= 0 ? .open
                : skippedDaysAgo.contains(daysAgo) ? .skipped(at: start, reason: "Schedule conflict")
                : done(at: end)
            result.append(HabitInstanceItem(
                title: habit.name,
                anchor: .timeBlock(start: start, end: end),
                completion: completion,
                habitID: habit.id,
                targetDuration: habit.targetDuration
            ))
        }
        return result
    }
}
#endif
