import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "habits")

actor HabitRepository {
    private let controller: PersistenceController

    init(controller: PersistenceController) {
        self.controller = controller
    }

    func fetchAll() async throws -> [Habit] {
        let context = controller.newBackgroundContext()
        let stored = try context.fetch(FetchDescriptor<StoredHabit>())
        return try stored.map { try habitFrom($0) }
    }

    func fetchInstances(in interval: DateInterval) async throws -> [HabitInstanceItem] {
        let context = controller.newBackgroundContext()
        let stored = try context.fetch(FetchDescriptor<StoredHabitInstance>())
        return try stored.compactMap { s -> HabitInstanceItem? in
            let item = try HabitInstanceItem.from(s)
            guard let d = item.anchor.sortDate else { return nil }
            return interval.contains(d) ? item : nil
        }
    }

    func add(_ habit: Habit) async throws {
        let context = controller.newBackgroundContext()
        context.insert(try storedFrom(habit))
        try context.save()
        logger.info("Added habit '\(habit.name)'")
        postChange()
    }

    func update(_ habit: Habit) async throws {
        let context = controller.newBackgroundContext()
        let stored = try context.fetch(FetchDescriptor<StoredHabit>())
        stored.filter { $0.id == habit.id }.forEach { context.delete($0) }
        context.insert(try storedFrom(habit))
        try context.save()
        postChange()
    }

    private nonisolated func postChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .leoDataDidChange, object: nil)
        }
    }

    func archive(id: UUID) async throws {
        let context = controller.newBackgroundContext()
        let stored = try context.fetch(FetchDescriptor<StoredHabit>())
        stored.filter { $0.id == id }.forEach { $0.isArchived = true }
        try context.save()
    }

    func allActive() async -> [Habit] {
        (try? await fetchAll().filter { !$0.isArchived }) ?? []
    }

    func instances(for habitID: UUID, in interval: DateInterval) async -> [HabitInstanceItem] {
        (try? await fetchInstances(in: interval).filter { $0.habitID == habitID }) ?? []
    }

    func addInstance(_ instance: HabitInstanceItem) async throws {
        let context = controller.newBackgroundContext()
        let s = StoredHabitInstance(
            id: instance.id, title: instance.title, notes: instance.notes,
            createdAt: instance.createdAt, updatedAt: instance.updatedAt,
            importanceRaw: instance.importance.rawValue,
            anchorData: try instance.anchor.encoded(),
            completionData: try instance.completion.encoded(),
            habitID: instance.habitID,
            targetDurationSeconds: instance.targetDuration.map { Double($0.components.seconds) }
        )
        context.insert(s)
        try context.save()
    }

    func updateInstance(_ instance: HabitInstanceItem) async throws {
        let context = controller.newBackgroundContext()
        let stored = try context.fetch(FetchDescriptor<StoredHabitInstance>())
        stored.filter { $0.id == instance.id }.forEach { context.delete($0) }
        let s = StoredHabitInstance(
            id: instance.id, title: instance.title, notes: instance.notes,
            createdAt: instance.createdAt, updatedAt: instance.updatedAt,
            importanceRaw: instance.importance.rawValue,
            anchorData: try instance.anchor.encoded(),
            completionData: try instance.completion.encoded(),
            habitID: instance.habitID,
            targetDurationSeconds: instance.targetDuration.map { Double($0.components.seconds) }
        )
        context.insert(s)
        try context.save()
    }

    // MARK: - Private

    private func habitFrom(_ stored: StoredHabit) throws -> Habit {
        let frequency = try JSONDecoder().decode(HabitFrequency.self, from: stored.frequencyData)
        let timeHint = try stored.timeHintData.map { try JSONDecoder().decode(TimeOfDay.self, from: $0) }
        let forgiveness = try JSONDecoder().decode(HabitForgiveness.self, from: stored.forgivenessData)
        return Habit(
            id: stored.id, name: stored.name, frequency: frequency,
            timeHint: timeHint,
            targetDuration: stored.targetDurationSeconds.map { .seconds($0) },
            recurrenceRule: RecurrenceRule(raw: stored.recurrenceRule?.raw ?? "FREQ=DAILY"),
            forgiveness: forgiveness,
            createdAt: stored.createdAt,
            isArchived: stored.isArchived
        )
    }

    private func storedFrom(_ habit: Habit) throws -> StoredHabit {
        StoredHabit(
            id: habit.id, name: habit.name,
            frequencyData: try JSONEncoder().encode(habit.frequency),
            timeHintData: try habit.timeHint.map { try JSONEncoder().encode($0) },
            targetDurationSeconds: habit.targetDuration.map { Double($0.components.seconds) },
            forgivenessData: try JSONEncoder().encode(habit.forgiveness),
            createdAt: habit.createdAt,
            isArchived: habit.isArchived
        )
    }
}
