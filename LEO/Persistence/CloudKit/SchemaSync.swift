import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.leo.app", category: "cloudkit")

/// Debug-only utility to push the schema to CloudKit by writing and deleting a sample record of each type.
/// CloudKit auto-creates record types on first write; this seeds the dev schema intentionally.
/// STOP AND ASK before doing the equivalent in production.
#if DEBUG
enum SchemaSync {
    static func forceSeed(controller: PersistenceController) async throws {
        logger.info("Forcing CloudKit schema seed...")
        let context = controller.newBackgroundContext()

        let anchorData = try Anchor.untimed.encoded()
        let completionData = try Completion.open.encoded()
        let habitFreqData = try JSONEncoder().encode(HabitFrequency.daily)
        let habitForgData = try JSONEncoder().encode(HabitForgiveness.none)

        let task = StoredTask(title: "_schema_seed_task", anchorData: anchorData, completionData: completionData)
        let event = StoredEvent(title: "_schema_seed_event", anchorData: anchorData, completionData: completionData)
        let reminder = StoredReminder(title: "_schema_seed_reminder", anchorData: anchorData, completionData: completionData)
        let alarm = StoredAlarm(title: "_schema_seed_alarm", anchorData: anchorData, completionData: completionData)
        let tag = StoredTag(name: "_schema_seed_tag")
        let rule = StoredRecurrenceRule(raw: "FREQ=DAILY")
        let habit = StoredHabit(
            name: "_schema_seed_habit",
            frequencyData: habitFreqData,
            forgivenessData: habitForgData
        )
        let instance = StoredHabitInstance(
            title: "_schema_seed_instance",
            anchorData: anchorData,
            completionData: completionData,
            habitID: habit.id
        )

        context.insert(task)
        context.insert(event)
        context.insert(reminder)
        context.insert(alarm)
        context.insert(tag)
        context.insert(rule)
        context.insert(habit)
        context.insert(instance)
        try context.save()

        // Immediately delete — the write itself registers record types with CloudKit
        context.delete(task)
        context.delete(event)
        context.delete(reminder)
        context.delete(alarm)
        context.delete(tag)
        context.delete(rule)
        context.delete(habit)
        context.delete(instance)
        try context.save()
        logger.info("Schema seed complete and records cleared.")
    }
}
#endif
