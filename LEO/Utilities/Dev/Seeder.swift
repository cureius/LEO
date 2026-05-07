import Foundation

/// Produces deterministic fixture data for development and testing.
/// No randomness when `randomize = false` (used in unit tests).
#if DEBUG
struct Seeder {
    let randomize: Bool

    init(randomize: Bool = true) {
        self.randomize = randomize
    }

    // MARK: - Item fixtures

    func makeTaskItems(count: Int = 10) -> [TaskItem] {
        let titles = ["Draft Q3 report", "Review PR #42", "Book flights", "Pay bills", "Call dentist",
                      "Write blog post", "Update resume", "Clean apartment", "Prepare slides", "Read chapter 5"]
        return (0..<count).map { i in
            let title = titles[i % titles.count]
            let daysOffset = Double(i) - 2
            let importance: Importance = [.low, .normal, .high, .urgent][i % 4]
            return TaskItem(
                title: title,
                importance: importance,
                anchor: .dueAt(Date.now.addingTimeInterval(daysOffset * 86400)),
                deadline: Date.now.addingTimeInterval(Double(i + 1) * 86400)
            )
        }
    }

    func makeEventItems(count: Int = 5) -> [EventItem] {
        let titles = ["Team standup", "Dentist", "Gym", "Coffee with Alex", "Product review"]
        let hours = [9, 10, 14, 16, 11]
        return (0..<count).map { i in
            let title = titles[i % titles.count]
            let start = Calendar.current.date(bySettingHour: hours[i % hours.count], minute: 0, second: 0, of: Date.now)!
            let end = start.addingTimeInterval(3600)
            return EventItem(title: title, anchor: .timeBlock(start: start, end: end), location: i == 1 ? "401 Pine St" : nil)
        }
    }

    func makeReminderItems(count: Int = 5) -> [ReminderItem] {
        let titles = ["Take medication", "Call mom", "Pick up groceries", "Submit expense report", "Water plants"]
        return (0..<count).map { i in
            let fireTime = Date.now.addingTimeInterval(Double(i + 1) * 3600)
            return ReminderItem(title: titles[i % titles.count], anchor: .point(fireTime))
        }
    }

    func makeAlarmItem() -> AlarmItem {
        AlarmItem(title: "Wake up", anchor: .point(
            Calendar.current.date(bySettingHour: 6, minute: 30, second: 0, of: Date.now.addingTimeInterval(86400))!
        ))
    }

    func makeHabitInstances(habitID: UUID, count: Int = 7) -> [HabitInstanceItem] {
        (0..<count).map { i in
            let start = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0,
                                               of: Date.now.addingTimeInterval(Double(i) * 86400))!
            let end = start.addingTimeInterval(3600)
            return HabitInstanceItem(
                title: "Gym",
                anchor: .timeBlock(start: start, end: end),
                habitID: habitID
            )
        }
    }

    // MARK: - Populate a repository

    func seedAll(itemRepository: ItemRepository, habitRepository: HabitRepository) async throws {
        for item in makeTaskItems() { try await itemRepository.add(item) }
        for item in makeEventItems() { try await itemRepository.add(item) }
        for item in makeReminderItems() { try await itemRepository.add(item) }
        try await itemRepository.add(makeAlarmItem())

        let gymHabit = Habit(
            name: "Gym",
            frequency: .specificDays([.monday, .wednesday, .friday]),
            timeHint: .morning,
            targetDuration: .seconds(3600),
            recurrenceRule: .weekly(on: [.monday, .wednesday, .friday]),
            forgiveness: .misses(perWeek: 1)
        )
        try await habitRepository.add(gymHabit)

        let meditationHabit = Habit(
            name: "Meditation",
            frequency: .daily,
            timeHint: .morning,
            targetDuration: .seconds(600),
            recurrenceRule: .daily(),
            forgiveness: .misses(perWeek: 1)
        )
        try await habitRepository.add(meditationHabit)

        for instance in makeHabitInstances(habitID: gymHabit.id) {
            try await habitRepository.addInstance(instance)
        }
    }
}
#endif
