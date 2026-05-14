import SwiftData
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "persistence")

// UserDefaults key used to opt in/out of CloudKit sync.
// Default: true. Set to false via -LEODisableCloudKitSync 1 launch argument to diagnose sync issues.
private let ckDisabledKey = "LEODisableCloudKitSync"

/// Central SwiftData container.
///
/// Current schema: SchemaV3 (adds rruleRaw to item types).
/// CloudKit sync is enabled by default when not in-memory.
/// Pass launch arg -LEODisableCloudKitSync 1 to disable for debugging.
final class PersistenceController {
    let container: ModelContainer

    init(useInMemory: Bool = false) {
        let ckEnabled = !useInMemory && !UserDefaults.standard.bool(forKey: ckDisabledKey)
        logger.info("PersistenceController init (inMemory=\(useInMemory), cloudKit=\(ckEnabled))")
        let schema = Schema(SchemaV3.models)

        do {
            container = try Self.makeContainer(schema: schema, useInMemory: useInMemory, cloudKit: ckEnabled)
            logger.info("PersistenceController ready")
        } catch {
            logger.fault("ModelContainer init failed: \(error) — attempting store reset")
            do {
                try Self.deleteOnDiskStore()
                container = try Self.makeContainer(schema: schema, useInMemory: false, cloudKit: ckEnabled)
                logger.warning("Store was reset after migration failure")
            } catch {
                logger.fault("Store reset also failed: \(error) — falling back to in-memory")
                container = try! Self.makeContainer(schema: schema, useInMemory: true, cloudKit: false)
            }
        }
    }

    // MARK: - Private helpers

    private static func makeContainer(schema: Schema, useInMemory: Bool, cloudKit: Bool) throws -> ModelContainer {
        let ckMode: ModelConfiguration.CloudKitDatabase = cloudKit ? .automatic : .none
        let config: ModelConfiguration
        if useInMemory {
            config = ModelConfiguration(
                "LEO-inMemory",
                schema: schema,
                url: URL(fileURLWithPath: "/dev/null"),
                cloudKitDatabase: .none
            )
        } else {
            config = ModelConfiguration("LEO", schema: schema, cloudKitDatabase: ckMode)
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
        let candidates = [storeURL, storeURL.appendingPathExtension("shm"), storeURL.appendingPathExtension("wal")]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            logger.warning("Deleted store file: \(url.lastPathComponent)")
        }
    }

    // MARK: - Contexts

    @MainActor
    var mainContext: ModelContext { container.mainContext }

    func newBackgroundContext() -> ModelContext { ModelContext(container) }
}
