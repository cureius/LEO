import SwiftData

/// Migration plan for the LEO schema. Empty in v1 — exists so future migrations have a home.
enum MigrationPlanV1: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
