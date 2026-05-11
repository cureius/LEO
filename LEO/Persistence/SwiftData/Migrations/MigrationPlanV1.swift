import SwiftData

/// Migration plan for LEO's SwiftData store.
///
/// V1 → V2: lightweight migration — adds StoredBodyProfile, StoredMeasurement,
/// StoredWorkoutItem, StoredMealItem. No existing columns changed.
enum MigrationPlanV1: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [stageV1toV2]
    }

    /// Lightweight (inferred) migration — SwiftData just adds the new tables.
    static let stageV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )
}
