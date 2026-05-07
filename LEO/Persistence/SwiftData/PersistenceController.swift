import SwiftData
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.leo.app", category: "persistence")

/// Central SwiftData container. All repositories get their ModelContext from here.
/// CloudKit configuration is in M0-T06; this actor owns the container lifetime.
final class PersistenceController {
    let container: ModelContainer

    /// - Parameter useInMemory: Pass `true` for tests and Xcode previews.
    init(useInMemory: Bool = false) {
        let schema = Schema(SchemaV1.models)
        let config: ModelConfiguration

        if useInMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            // CloudKit private DB sync wired in M0-T06.
            // For now: persistent store, no CloudKit until capability is configured.
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: MigrationPlanV1.self,
                configurations: config
            )
            logger.info("PersistenceController initialized (inMemory=\(useInMemory))")
        } catch {
            logger.error("Failed to create ModelContainer: \(error)")
            fatalError("Cannot create ModelContainer: \(error)")
        }
    }

    /// A new background context for off-main-thread work.
    @MainActor
    var mainContext: ModelContext { container.mainContext }

    func newBackgroundContext() -> ModelContext {
        ModelContext(container)
    }
}
