import SwiftData
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "persistence")

/// Central SwiftData container.
///
/// CloudKit integration is deferred to M3. Until then, all configurations use
/// `.cloudKitDatabase(.none)` to bypass CloudKit schema validation — which
/// requires all attributes to be optional and all relationships to have inverses.
/// When M3 arrives, the @Model types will be made CloudKit-compliant and this
/// will switch to `.cloudKitDatabase(.private("iCloud.com.theblueman.leo"))`.
final class PersistenceController {
    let container: ModelContainer

    init(useInMemory: Bool = false) {
        logger.info("PersistenceController init start (inMemory=\(useInMemory))")
        let schema = Schema(SchemaV1.models)

        do {
            let config: ModelConfiguration
            if useInMemory {
                // In-memory: use /dev/null path with explicit .none to skip CloudKit validation
                config = ModelConfiguration(
                    "LEO-inMemory",
                    schema: schema,
                    url: URL(fileURLWithPath: "/dev/null"),
                    cloudKitDatabase: .none
                )
            } else {
                // On-disk: explicit .none until M3 CloudKit work
                config = ModelConfiguration(
                    "LEO",
                    schema: schema,
                    cloudKitDatabase: .none
                )
            }

            container = try ModelContainer(
                for: schema,
                migrationPlan: MigrationPlanV1.self,
                configurations: config
            )
            logger.info("PersistenceController initialized OK (inMemory=\(useInMemory))")
        } catch {
            logger.fault("ModelContainer init failed: \(error)")
            fatalError("Cannot create ModelContainer: \(error)")
        }
    }

    @MainActor
    var mainContext: ModelContext { container.mainContext }

    func newBackgroundContext() -> ModelContext {
        ModelContext(container)
    }
}
