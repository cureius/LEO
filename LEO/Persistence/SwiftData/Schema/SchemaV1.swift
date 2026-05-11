import SwiftData

/// Version 1 of the LEO data schema.
/// Once deployed to CloudKit production (at M3), all field types here are frozen — only additions allowed.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            StoredTask.self,
            StoredEvent.self,
            StoredReminder.self,
            StoredAlarm.self,
            StoredHabit.self,
            StoredHabitInstance.self,
            StoredTag.self,
            StoredRecurrenceRule.self,
            StoredOverride.self,
        ]
    }
}
