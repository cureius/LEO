import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "snapshot")

// MARK: - Result

struct SnapshotRestoreResult {
    var itemsRestored: Int = 0
    var habitsRestored: Int = 0
    var instancesRestored: Int = 0
    var measurementsRestored: Int = 0
    var profileRestored: Bool = false
    var skipped: Int = 0
}

// MARK: - Restore mode

enum SnapshotRestoreMode {
    /// Only insert records whose ID doesn't already exist in the store.
    case merge
    /// Wipe all LEO data first, then restore everything from the snapshot.
    case replace
}

// MARK: - Service

actor SnapshotService {
    private let itemRepo: ItemRepository
    private let habitRepo: HabitRepository
    private let bodyProfileRepo: BodyProfileRepository

    init(itemRepo: ItemRepository, habitRepo: HabitRepository, bodyProfileRepo: BodyProfileRepository) {
        self.itemRepo = itemRepo
        self.habitRepo = habitRepo
        self.bodyProfileRepo = bodyProfileRepo
    }

    // MARK: - Export

    func exportData() async throws -> Data {
        async let items = try itemRepo.fetch()
        async let habits = try habitRepo.fetchAll()
        async let measurements = bodyProfileRepo.allMeasurements()
        async let profile = bodyProfileRepo.load()

        let (allItems, allHabits, allMeasurements, bodyProfile) =
            try await (items, habits, measurements, profile)

        let snapshot = AppSnapshot(
            version: AppSnapshot.currentVersion,
            exportedAt: .now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            tasks:          allItems.compactMap { $0 as? TaskItem }        .compactMap { try? SnapshotTask(from: $0) },
            events:         allItems.compactMap { $0 as? EventItem }       .compactMap { try? SnapshotEvent(from: $0) },
            reminders:      allItems.compactMap { $0 as? ReminderItem }    .compactMap { try? SnapshotReminder(from: $0) },
            alarms:         allItems.compactMap { $0 as? AlarmItem }       .compactMap { try? SnapshotAlarm(from: $0) },
            habitInstances: allItems.compactMap { $0 as? HabitInstanceItem }.compactMap { try? SnapshotHabitInstance(from: $0) },
            workouts:       allItems.compactMap { $0 as? WorkoutItem }     .compactMap { try? SnapshotWorkout(from: $0) },
            meals:          allItems.compactMap { $0 as? MealItem }        .compactMap { try? SnapshotMeal(from: $0) },
            habits:         allHabits.map(SnapshotHabit.init),
            bodyProfile:    bodyProfile,
            measurements:   allMeasurements
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        logger.info("Snapshot exported: \(data.count) bytes, \(allItems.count) items, \(allHabits.count) habits")
        return data
    }

    // MARK: - Import

    func restoreData(from data: Data, mode: SnapshotRestoreMode) async throws -> SnapshotRestoreResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(AppSnapshot.self, from: data)

        guard snapshot.version <= AppSnapshot.currentVersion else {
            throw SnapshotError.unsupportedVersion(snapshot.version)
        }

        if mode == .replace {
            try await wipeAll()
        }

        return try await restoreFrom(snapshot, mode: mode)
    }

    // MARK: - Private: wipe

    private func wipeAll() async throws {
        // Habits first — cascade rule deletes StoredHabitInstances
        try await habitRepo.deleteAll()
        // Remaining items (Tasks, Events, Reminders, Alarms, Workouts, Meals)
        let remaining = try await itemRepo.fetch()
        try await itemRepo.deleteBatch(ids: remaining.map(\.id))
        // Measurements (body profile singleton is overwritten on restore, no explicit delete)
        try await bodyProfileRepo.deleteAllMeasurements()
        logger.info("Snapshot wipe complete")
    }

    // MARK: - Private: restore pass

    private func restoreFrom(_ snapshot: AppSnapshot, mode: SnapshotRestoreMode) async throws -> SnapshotRestoreResult {
        var result = SnapshotRestoreResult()

        // In merge mode build a set of existing IDs to skip duplicates
        let existingItemIDs: Set<UUID>
        let existingHabitIDs: Set<UUID>
        let existingMeasurementIDs: Set<UUID>

        if mode == .merge {
            let existingItems = try await itemRepo.fetch()
            existingItemIDs = Set(existingItems.map(\.id))
            existingHabitIDs = Set(try await habitRepo.fetchAll().map(\.id))
            existingMeasurementIDs = Set((await bodyProfileRepo.allMeasurements()).map(\.id))
        } else {
            existingItemIDs = []; existingHabitIDs = []; existingMeasurementIDs = []
        }

        // Items (TaskItem, EventItem, etc.)
        var itemsToAdd: [any Item] = []
        func collect<S: SnapshotItemConvertible>(_ dtos: [S]) {
            for dto in dtos {
                guard !existingItemIDs.contains(dto.itemID) else { result.skipped += 1; continue }
                if let item = try? dto.toAnyItem() { itemsToAdd.append(item) }
            }
        }
        collect(snapshot.tasks)
        collect(snapshot.events)
        collect(snapshot.reminders)
        collect(snapshot.alarms)
        collect(snapshot.workouts)
        collect(snapshot.meals)
        try await itemRepo.addBatch(itemsToAdd)
        result.itemsRestored = itemsToAdd.count

        // Habits
        var habitsToAdd: [Habit] = []
        var instancesToAdd: [HabitInstanceItem] = []
        for dto in snapshot.habits {
            if !existingHabitIDs.contains(dto.id) { habitsToAdd.append(dto.toHabit()) }
            else { result.skipped += 1 }
        }
        for dto in snapshot.habitInstances {
            if !existingItemIDs.contains(dto.id), !existingHabitIDs.contains(dto.habitID) || mode == .replace {
                if let inst = try? dto.toItem() { instancesToAdd.append(inst) }
            } else if existingItemIDs.contains(dto.id) {
                result.skipped += 1
            }
        }
        for habit in habitsToAdd { try await habitRepo.add(habit) }
        result.habitsRestored = habitsToAdd.count
        try await habitRepo.addInstanceBatch(instancesToAdd)
        result.instancesRestored = instancesToAdd.count

        // Body profile (replace always, merge only if absent)
        if let profile = snapshot.bodyProfile {
            let existingProfile = await bodyProfileRepo.load()
            let hasExisting = mode == .merge && existingProfile != nil
            if !hasExisting {
                try await bodyProfileRepo.save(profile)
                result.profileRestored = true
            }
        }

        // Measurements
        let newMeasurements = snapshot.measurements.filter { !existingMeasurementIDs.contains($0.id) }
        result.skipped += snapshot.measurements.count - newMeasurements.count
        try await bodyProfileRepo.appendMeasurementBatch(newMeasurements)
        result.measurementsRestored = newMeasurements.count

        logger.info("Snapshot restored: \(result.itemsRestored) items, \(result.habitsRestored) habits, \(result.instancesRestored) instances, skipped \(result.skipped)")
        return result
    }
}

// MARK: - Protocol to unify DTO → Item conversion

private protocol SnapshotItemConvertible {
    var itemID: UUID { get }
    func toAnyItem() throws -> any Item
}

extension SnapshotTask:          SnapshotItemConvertible { var itemID: UUID { id }; func toAnyItem() throws -> any Item { try toItem() } }
extension SnapshotEvent:         SnapshotItemConvertible { var itemID: UUID { id }; func toAnyItem() throws -> any Item { try toItem() } }
extension SnapshotReminder:      SnapshotItemConvertible { var itemID: UUID { id }; func toAnyItem() throws -> any Item { try toItem() } }
extension SnapshotAlarm:         SnapshotItemConvertible { var itemID: UUID { id }; func toAnyItem() throws -> any Item { try toItem() } }
extension SnapshotWorkout:       SnapshotItemConvertible { var itemID: UUID { id }; func toAnyItem() throws -> any Item { try toItem() } }
extension SnapshotMeal:          SnapshotItemConvertible { var itemID: UUID { id }; func toAnyItem() throws -> any Item { try toItem() } }
