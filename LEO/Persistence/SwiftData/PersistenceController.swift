import SwiftData
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "persistence")

/// Central SwiftData container.
///
/// Current schema: SchemaV2 (adds Gym Companion models).
/// Migration plan: V1 → V2 via lightweight migration (new tables only).
/// CloudKit deferred to M3; all configs use `.cloudKitDatabase(.none)`.
final class PersistenceController {
    let container: ModelContainer

    init(useInMemory: Bool = false) {
        logger.info("PersistenceController init (inMemory=\(useInMemory))")
        // Always use V2 schema (the latest) when building the container.
        let schema = Schema(SchemaV2.models)

        do {
            container = try Self.makeContainer(schema: schema, useInMemory: useInMemory)
            logger.info("PersistenceController ready")
        } catch {
            // Migration failed (can happen when a beta build's store is corrupted or
            // has an incompatible shape). Attempt recovery by deleting the on-disk
            // store and starting fresh — acceptable in development; data is lost but
            // the app doesn't crash.
            logger.fault("ModelContainer init failed: \(error) — attempting store reset")
            do {
                try Self.deleteOnDiskStore()
                container = try Self.makeContainer(schema: schema, useInMemory: false)
                logger.warning("Store was reset after migration failure")
            } catch {
                // Absolute last resort: in-memory store so the app stays alive
                logger.fault("Store reset also failed: \(error) — falling back to in-memory")
                container = try! Self.makeContainer(schema: schema, useInMemory: true)
            }
        }
    }

    // MARK: - Private helpers

    private static func makeContainer(schema: Schema, useInMemory: Bool) throws -> ModelContainer {
        let config: ModelConfiguration
        if useInMemory {
            config = ModelConfiguration(
                "LEO-inMemory",
                schema: schema,
                url: URL(fileURLWithPath: "/dev/null"),
                cloudKitDatabase: .none
            )
        } else {
            config = ModelConfiguration(
                "LEO",
                schema: schema,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: MigrationPlanV1.self,
            configurations: config
        )
    }

    private static func deleteOnDiskStore() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = appSupport.appendingPathComponent("LEO.store")
        let candidates = [
            storeURL,
            storeURL.appendingPathExtension("shm"),
            storeURL.appendingPathExtension("wal"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            logger.warning("Deleted store file: \(url.lastPathComponent)")
        }
    }

    // MARK: - Contexts

    @MainActor
    var mainContext: ModelContext { container.mainContext }

    func newBackgroundContext() -> ModelContext {
        ModelContext(container)
    }
}
