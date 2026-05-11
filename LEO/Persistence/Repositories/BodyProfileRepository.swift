import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "body-profile-repo")

actor BodyProfileRepository {
    private let controller: PersistenceController

    init(controller: PersistenceController) {
        self.controller = controller
    }

    // MARK: - Profile

    func load() async -> UserBodyProfile? {
        let context = controller.newBackgroundContext()
        let descriptor = FetchDescriptor<StoredBodyProfile>()
        guard let stored = (try? context.fetch(descriptor))?.first else { return nil }
        return UserBodyProfile.from(stored)
    }

    func save(_ profile: UserBodyProfile) async throws {
        let context = controller.newBackgroundContext()
        // Delete existing singleton row
        let existing = try context.fetch(FetchDescriptor<StoredBodyProfile>())
        existing.forEach { context.delete($0) }
        context.insert(StoredBodyProfile(from: profile))
        try context.save()
        logger.info("Body profile saved")
        postChange()
    }

    // MARK: - Measurements

    func appendMeasurement(_ m: BodyMeasurement) async throws {
        let context = controller.newBackgroundContext()
        context.insert(StoredMeasurement(from: m))
        try context.save()
        logger.info("Measurement appended: \(m.weightKg) kg")
        postChange()
    }

    func recentMeasurements(limit: Int = 90) async -> [BodyMeasurement] {
        let context = controller.newBackgroundContext()
        var descriptor = FetchDescriptor<StoredMeasurement>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let stored = (try? context.fetch(descriptor)) ?? []
        return stored.map(BodyMeasurement.from)
    }

    func deleteMeasurement(id: UUID) async throws {
        let context = controller.newBackgroundContext()
        let all = try context.fetch(FetchDescriptor<StoredMeasurement>())
        all.filter { $0.id == id }.forEach { context.delete($0) }
        try context.save()
    }

    // MARK: - Private

    private nonisolated func postChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .leoDataDidChange, object: nil)
        }
    }
}
