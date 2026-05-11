import SwiftData

/// Schema version 2 — adds Gym Companion models (M8).
/// Lightweight migration from V1: only new tables, no column changes.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

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
            // M8: Gym Companion
            StoredBodyProfile.self,
            StoredMeasurement.self,
            StoredWorkoutItem.self,
            StoredMealItem.self,
        ]
    }
}
