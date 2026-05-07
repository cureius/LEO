import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.leo.app", category: "repository")

/// Central read/write repository for all Item kinds.
/// Views never call this directly — they go through view models.
actor ItemRepository {
    private let controller: PersistenceController

    init(controller: PersistenceController) {
        self.controller = controller
    }

    // MARK: - Fetch

    func fetch(predicate: ItemPredicate = .all) async throws -> [any Item] {
        let context = controller.newBackgroundContext()
        var results: [any Item] = []

        switch predicate {
        case .all, .inDateInterval, .onDay, .byID, .untimed, .completionFilter:
            results += try fetchTasks(predicate: predicate, context: context)
            results += try fetchEvents(predicate: predicate, context: context)
            results += try fetchReminders(predicate: predicate, context: context)
            results += try fetchAlarms(predicate: predicate, context: context)
            results += try fetchHabitInstances(predicate: predicate, context: context)
        }

        return results.sorted { ($0.anchor.sortDate ?? .distantFuture) < ($1.anchor.sortDate ?? .distantFuture) }
    }

    // MARK: - Write

    func add(_ item: any Item) async throws {
        let context = controller.newBackgroundContext()
        try insertItem(item, context: context)
        try context.save()
        logger.info("Added item \(item.id) '\(item.title)'")
    }

    func update(_ item: any Item) async throws {
        let context = controller.newBackgroundContext()
        try deleteStored(id: item.id, context: context)
        try insertItem(item, context: context)
        try context.save()
    }

    func delete(id: UUID) async throws {
        let context = controller.newBackgroundContext()
        try deleteStored(id: id, context: context)
        try context.save()
    }

    // MARK: - Change stream

    nonisolated func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            // SwiftData doesn't expose a cross-context change stream in iOS 17.
            // Polling-based approach: M1 will wire a proper notification observer.
            // For now, callers can call fetch() at will; stream yields once on subscribe.
            continuation.yield()
        }
    }

    // MARK: - Private helpers

    private func fetchTasks(predicate: ItemPredicate, context: ModelContext) throws -> [any Item] {
        let descriptor = FetchDescriptor<StoredTask>()
        let stored = try context.fetch(descriptor)
        let items = try stored.compactMap { s -> TaskItem? in
            let item = try TaskItem.from(s)
            return matches(item, predicate: predicate) ? item : nil
        }
        return items
    }

    private func fetchEvents(predicate: ItemPredicate, context: ModelContext) throws -> [any Item] {
        let stored = try context.fetch(FetchDescriptor<StoredEvent>())
        return try stored.compactMap { s -> EventItem? in
            let item = try EventItem.from(s)
            return matches(item, predicate: predicate) ? item : nil
        }
    }

    private func fetchReminders(predicate: ItemPredicate, context: ModelContext) throws -> [any Item] {
        let stored = try context.fetch(FetchDescriptor<StoredReminder>())
        return try stored.compactMap { s -> ReminderItem? in
            let item = try ReminderItem.from(s)
            return matches(item, predicate: predicate) ? item : nil
        }
    }

    private func fetchAlarms(predicate: ItemPredicate, context: ModelContext) throws -> [any Item] {
        let stored = try context.fetch(FetchDescriptor<StoredAlarm>())
        return try stored.compactMap { s -> AlarmItem? in
            let item = try AlarmItem.from(s)
            return matches(item, predicate: predicate) ? item : nil
        }
    }

    private func fetchHabitInstances(predicate: ItemPredicate, context: ModelContext) throws -> [any Item] {
        let stored = try context.fetch(FetchDescriptor<StoredHabitInstance>())
        return try stored.compactMap { s -> HabitInstanceItem? in
            let item = try HabitInstanceItem.from(s)
            return matches(item, predicate: predicate) ? item : nil
        }
    }

    private func matches(_ item: any Item, predicate: ItemPredicate) -> Bool {
        switch predicate {
        case .all: return true
        case .byID(let id): return item.id == id
        case .untimed: return item.anchor.isUntimed
        case .completionFilter(let f):
            switch f {
            case .all: return true
            case .open: return !item.isCompleted
            case .finished: return item.isCompleted
            }
        case .inDateInterval(let interval):
            guard let d = item.anchor.sortDate else { return false }
            return interval.contains(d)
        case .onDay(let day):
            guard let d = item.anchor.sortDate else { return false }
            return Calendar.current.isDate(d, inSameDayAs: day)
        }
    }

    private func insertItem(_ item: any Item, context: ModelContext) throws {
        if let t = item as? TaskItem {
            context.insert(try StoredTask(from: t))
        } else if let e = item as? EventItem {
            context.insert(try StoredEvent(from: e))
        } else if let r = item as? ReminderItem {
            context.insert(try StoredReminder(from: r))
        } else if let a = item as? AlarmItem {
            context.insert(try StoredAlarm(from: a))
        } else if item is HabitInstanceItem {
            // HabitInstances are managed by HabitRepository
        } else {
            logger.error("Unknown item type: \(type(of: item))")
        }
    }

    private func deleteStored(id: UUID, context: ModelContext) throws {
        let taskItems = try context.fetch(FetchDescriptor<StoredTask>())
        taskItems.filter { $0.id == id }.forEach { context.delete($0) }
        let events = try context.fetch(FetchDescriptor<StoredEvent>())
        events.filter { $0.id == id }.forEach { context.delete($0) }
        let reminders = try context.fetch(FetchDescriptor<StoredReminder>())
        reminders.filter { $0.id == id }.forEach { context.delete($0) }
        let alarms = try context.fetch(FetchDescriptor<StoredAlarm>())
        alarms.filter { $0.id == id }.forEach { context.delete($0) }
        let instances = try context.fetch(FetchDescriptor<StoredHabitInstance>())
        instances.filter { $0.id == id }.forEach { context.delete($0) }
    }
}
