import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "series")

/// Manages per-occurrence overrides for recurring series.
/// Each override is keyed by the *canonical* occurrence date the engine produces before any override.
actor SeriesRepository {
    private let controller: PersistenceController

    init(controller: PersistenceController) {
        self.controller = controller
    }

    // MARK: - Fetch

    /// Load all overrides for a series as a dictionary keyed by canonical date.
    func overrides(for seriesID: UUID) async throws -> [Date: SeriesOverride] {
        let context = controller.newBackgroundContext()
        let all = try context.fetch(FetchDescriptor<StoredOverride>())
        let matching = all.filter { $0.seriesID == seriesID }
        var result: [Date: SeriesOverride] = [:]
        for stored in matching {
            if let override = try? JSONDecoder().decode(SeriesOverride.self, from: stored.overrideData) {
                result[stored.canonicalDate] = override
            }
        }
        return result
    }

    // MARK: - Skip

    func skipOccurrence(seriesID: UUID, date: Date, reason: String? = nil) async throws {
        try await upsertOverride(seriesID: seriesID, date: date, override: .skip(reason: reason))
        logger.info("Skipped occurrence \(date) for series \(seriesID)")
    }

    // MARK: - Move

    func moveOccurrence(seriesID: UUID, originalDate: Date, start: Date, end: Date) async throws {
        try await upsertOverride(seriesID: seriesID, date: originalDate, override: .move(start: start, end: end))
        logger.info("Moved occurrence \(originalDate) → \(start) for series \(seriesID)")
    }

    // MARK: - Field override

    func patchOccurrence(seriesID: UUID, date: Date, patch: ItemPatch) async throws {
        try await upsertOverride(seriesID: seriesID, date: date, override: .fieldsOnly(patch))
    }

    // MARK: - Clear

    func clearOverride(seriesID: UUID, date: Date) async throws {
        let context = controller.newBackgroundContext()
        let all = try context.fetch(FetchDescriptor<StoredOverride>())
        let match = all.first { $0.seriesID == seriesID && Calendar.current.isDate($0.canonicalDate, inSameDayAs: date) }
        if let match { context.delete(match) }
        try context.save()
    }

    func clearAllOverrides(for seriesID: UUID) async throws {
        let context = controller.newBackgroundContext()
        let all = try context.fetch(FetchDescriptor<StoredOverride>())
        all.filter { $0.seriesID == seriesID }.forEach { context.delete($0) }
        try context.save()
    }

    // MARK: - Private

    private func upsertOverride(seriesID: UUID, date: Date, override: SeriesOverride) async throws {
        let data = try JSONEncoder().encode(override)
        let context = controller.newBackgroundContext()
        let all = try context.fetch(FetchDescriptor<StoredOverride>())
        if let existing = all.first(where: { $0.seriesID == seriesID && Calendar.current.isDate($0.canonicalDate, inSameDayAs: date) }) {
            existing.overrideData = data
        } else {
            context.insert(StoredOverride(seriesID: seriesID, canonicalDate: date, overrideData: data))
        }
        try context.save()
    }
}
