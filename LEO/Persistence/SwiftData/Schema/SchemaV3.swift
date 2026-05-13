import SwiftData

/// Schema version 3 — adds `rruleRaw: String?` to stored item types so recurring
/// occurrences carry their RFC 5545 rule string.
/// Lightweight migration from V2: only new nullable columns, no existing data changed.
enum SchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

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
            StoredBodyProfile.self,
            StoredMeasurement.self,
            StoredWorkoutItem.self,
            StoredMealItem.self,
        ]
    }
}
