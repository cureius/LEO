import SwiftData

/// Migration plan for LEO's SwiftData store.
///
/// SwiftData computes a checksum for each VersionedSchema from the actual class
/// definitions at runtime. Keeping V2 and V3 in the same plan causes a
/// "Duplicate version checksums detected" crash because both reference the same
/// (now-updated) model classes and produce identical checksums.
///
/// Solution: skip the intermediate V2 entry and migrate V1 → V3 in one
/// lightweight step. V1 uses a different model set (no Gym Companion or
/// rruleRaw tables), so its checksum differs from V3. V2 stores already on
/// device are purely additive relative to V3 (only nullable columns differ)
/// and SwiftData auto-migrates them without an explicit stage.
enum MigrationPlanV1: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [stageV1toV3]
    }

    /// Lightweight (inferred) migration — adds new tables and nullable columns.
    static let stageV1toV3 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV3.self
    )
}
