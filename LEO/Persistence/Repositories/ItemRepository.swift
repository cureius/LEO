import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "repository")

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
            results += try fetchWorkouts(predicate: predicate, context: context)
            results += try fetchMeals(predicate: predicate, context: context)
        }

        return results.sorted { ($0.anchor.sortDate ?? .distantFuture) < ($1.anchor.sortDate ?? .distantFuture) }
    }

    // MARK: - Write

    func add(_ item: any Item) async throws {
        let context = controller.newBackgroundContext()
        try insertItem(item, context: context)
        try context.save()
        logger.info("Added item \(item.id) '\(item.title)'")
        await refreshWidgetSnapshot()
        postChange()
    }

    /// Persist an edited item.
    ///
    /// `updatedAt` is refreshed to now by default, because a stale timestamp makes
    /// the change invisible to cloud sync: the push filter is `updatedAt > lastSync`,
    /// so an edit that doesn't advance the timestamp is never uploaded. Most callers
    /// (completing, rescheduling, editing) previously had to remember to bump it and
    /// many didn't — so completions silently failed to sync.
    ///
    /// Pass `preservingTimestamp: true` when applying a change that already carries an
    /// authoritative timestamp from elsewhere — a row pulled from the cloud, or a
    /// calendar event mirrored from EventKit — otherwise re-stamping it would defeat
    /// last-writer-wins and bounce the row back to its origin on the next sync.
    func update(_ item: any Item, preservingTimestamp: Bool = false) async throws {
        var item = item
        if !preservingTimestamp { item.updatedAt = .now }
        let context = controller.newBackgroundContext()
        try deleteStored(id: item.id, context: context)
        try insertItem(item, context: context)
        try context.save()
        await refreshWidgetSnapshot()
        postChange()
    }

    /// Change an item's id, atomically, preserving everything else about it.
    ///
    /// Used by EventKitBridge to migrate an already-mirrored calendar/reminders
    /// item from its old random per-device id onto the new id derived from
    /// `ExternalRef.deterministicItemID` — the id every device now converges on
    /// for the same real external event, required before it's safe to push these
    /// items to the cloud (SupabaseSync.push).
    ///
    /// Deliberately NOT implemented as `delete(id: oldID)` followed by
    /// `add(newItem)` as two separate actor calls: if `add` throws after
    /// `delete` succeeds, the local mirror is gone outright — not merely
    /// duplicated, since EventKit will re-import it as fresh on the next sync,
    /// silently dropping whatever local-only state (completion, tags,
    /// importance) the caller was trying to carry forward. One `ModelContext`
    /// and one `save()`, mirroring `update()`'s existing atomicity above, makes
    /// this a single transaction instead.
    func rekey(from oldID: UUID, to newItem: any Item) async throws {
        let context = controller.newBackgroundContext()
        try deleteStored(id: oldID, context: context)
        try insertItem(newItem, context: context)
        try context.save()
        logger.info("Rekeyed item \(oldID) -> \(newItem.id) '\(newItem.title)'")
        await refreshWidgetSnapshot()
        postChange()
    }

    func delete(id: UUID) async throws {
        let context = controller.newBackgroundContext()
        try deleteStored(id: id, context: context)
        try context.save()
        await refreshWidgetSnapshot()
        postChange()
    }

    /// Delete many items in a single SwiftData transaction and post one change notification.
    func deleteBatch(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let context = controller.newBackgroundContext()
        for id in ids {
            try deleteStored(id: id, context: context)
        }
        try context.save()
        logger.info("Batch-deleted \(ids.count) items")
        await refreshWidgetSnapshot()
        postChange()
    }

    /// Insert many items in a single SwiftData transaction and post one change notification.
    func addBatch(_ items: [any Item]) async throws {
        guard !items.isEmpty else { return }
        let context = controller.newBackgroundContext()
        for item in items {
            try insertItem(item, context: context)
        }
        try context.save()
        logger.info("Batch-added \(items.count) items")
        await refreshWidgetSnapshot()
        postChange()
    }

    private nonisolated func postChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .leoDataDidChange, object: nil)
        }
    }

    private func refreshWidgetSnapshot() async {
        guard let items = try? await fetch(predicate: .all) else { return }
        let today = Date.now
        let start = Calendar.current.startOfDay(for: today)
        let end = start.addingTimeInterval(86400)
        let interval = DateInterval(start: start, end: end)

        let todayItems = items
            .filter { item -> Bool in
                guard let d = item.anchor.sortDate else { return false }
                return interval.contains(d)
            }
            .prefix(5)
            .map { item in
                WidgetSnapshot.SnapshotItem(
                    id: item.id,
                    title: item.title,
                    time: item.anchor.sortDate,
                    typeSymbol: symbolName(for: item),
                    isCompleted: item.isCompleted
                )
            }

        let nextItem = todayItems.first(where: { !$0.isCompleted })

        let snapshot = WidgetSnapshot(
            todayItems: Array(todayItems),
            nextItem: nextItem,
            habitRing: WidgetSnapshot.HabitRingSummary(total: 0, completed: 0)
        )
        WidgetSnapshotStore.write(snapshot)
    }

    private func symbolName(for item: any Item) -> String {
        switch item {
        case is EventItem:         return "calendar"
        case is ReminderItem:      return "bell"
        case is AlarmItem:         return "alarm"
        case is HabitInstanceItem: return "repeat.circle"
        case is WorkoutItem:       return "figure.strengthtraining.traditional"
        case is MealItem:          return "fork.knife"
        default:                   return "checklist"
        }
    }

    private func fetchWorkouts(predicate: ItemPredicate, context: ModelContext) throws -> [any Item] {
        let stored = try context.fetch(FetchDescriptor<StoredWorkoutItem>())
        return try stored.compactMap { s -> WorkoutItem? in
            let item = try WorkoutItem.from(s)
            return matches(item, predicate: predicate) ? item : nil
        }
    }

    private func fetchMeals(predicate: ItemPredicate, context: ModelContext) throws -> [any Item] {
        let stored = try context.fetch(FetchDescriptor<StoredMealItem>())
        return try stored.compactMap { s -> MealItem? in
            let item = try MealItem.from(s)
            return matches(item, predicate: predicate) ? item : nil
        }
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
        } else if let w = item as? WorkoutItem {
            context.insert(try StoredWorkoutItem(from: w))
        } else if let m = item as? MealItem {
            context.insert(try StoredMealItem(from: m))
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
        let workouts = try context.fetch(FetchDescriptor<StoredWorkoutItem>())
        workouts.filter { $0.id == id }.forEach { context.delete($0) }
        let meals = try context.fetch(FetchDescriptor<StoredMealItem>())
        meals.filter { $0.id == id }.forEach { context.delete($0) }
    }
}
