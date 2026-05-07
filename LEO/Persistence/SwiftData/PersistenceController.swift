import SwiftData
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.leo.app", category: "persistence")

/// Central SwiftData container. All repositories get their ModelContext from here.
final class PersistenceController {
    let container: ModelContainer

    init(useInMemory: Bool = false) {
        logger.info("PersistenceController init start (inMemory=\(useInMemory))")
        let schema = Schema(SchemaV1.models)
        let config: ModelConfiguration

        if useInMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: MigrationPlanV1.self,
                configurations: config
            )
            logger.info("PersistenceController initialized OK (inMemory=\(useInMemory))")
        } catch {
            // On failure, fall back to in-memory so the app still launches
            logger.error("ModelContainer init failed: \(error) — falling back to in-memory")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                container = try ModelContainer(
                    for: schema,
                    migrationPlan: MigrationPlanV1.self,
                    configurations: fallback
                )
                logger.warning("Running on in-memory fallback store — data will NOT persist")
            } catch {
                logger.fault("Even in-memory ModelContainer failed: \(error)")
                fatalError("Cannot create any ModelContainer: \(error)")
            }
        }
    }

    @MainActor
    var mainContext: ModelContext { container.mainContext }

    func newBackgroundContext() -> ModelContext {
        ModelContext(container)
    }
}
