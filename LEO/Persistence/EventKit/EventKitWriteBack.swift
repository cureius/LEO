import EventKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "eventkit-write")

/// Writes LEO items back to EventKit calendars/reminder lists.
/// Only items without an `externalRef` (newly created in LEO) get written back;
/// items already sourced from EventKit update their existing EK record.
///
/// Conflict policy:
/// - Time fields: last-write-wins (compare EKEvent.lastModifiedDate vs Item.updatedAt)
/// - LEO-only metadata: always win (importance, tags, recurrence extensions — not sent to EK)
/// - Native-only metadata: native always wins (attendee objects, calendar color)
/// - Deletion: bi-directional — deleting in either app removes in the other on next sync
actor EventKitWriteBack {
    private let store = EKEventStore()

    // User-configured default write-back targets (stored in UserDefaults by settings)
    var defaultCalendarID: String? {
        UserDefaults.standard.string(forKey: "ek_default_calendar_id")
    }
    var defaultReminderListID: String? {
        UserDefaults.standard.string(forKey: "ek_default_reminder_list_id")
    }

    // MARK: - EventItem → EKEvent

    func writeBack(_ event: EventItem) async throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }

        let ekEvent: EKEvent
        if let ref = event.externalRef, ref.source == .eventKit,
           let existing = store.event(withIdentifier: ref.identifier) {
            // Update existing — conflict check: only update if LEO is newer
            if let ekModified = existing.lastModifiedDate, ekModified > event.updatedAt {
                logger.info("Skipping write-back for \(event.id): EventKit version is newer")
                return
            }
            ekEvent = existing
        } else {
            ekEvent = EKEvent(eventStore: store)
            if let calID = defaultCalendarID,
               let cal = store.calendar(withIdentifier: calID) {
                ekEvent.calendar = cal
            } else {
                ekEvent.calendar = store.defaultCalendarForNewEvents
            }
        }

        ekEvent.title = event.title
        ekEvent.notes = event.notes
        if case .timeBlock(let start, let end) = event.anchor {
            ekEvent.startDate = start
            ekEvent.endDate = end
        }
        ekEvent.location = event.location

        try store.save(ekEvent, span: .thisEvent, commit: true)
        logger.info("Wrote back event '\(event.title)' to EventKit")
    }

    // MARK: - ReminderItem → EKReminder

    func writeBack(_ reminder: ReminderItem) async throws {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }

        let ekReminder: EKReminder
        if let ref = reminder.externalRef, ref.source == .eventKit,
           let existing = store.calendarItem(withIdentifier: ref.identifier) as? EKReminder {
            ekReminder = existing
        } else {
            ekReminder = EKReminder(eventStore: store)
            if let listID = defaultReminderListID,
               let list = store.calendar(withIdentifier: listID) {
                ekReminder.calendar = list
            } else {
                ekReminder.calendar = store.defaultCalendarForNewReminders()
            }
        }

        ekReminder.title = reminder.title
        ekReminder.notes = reminder.notes
        if case .point(let date) = reminder.anchor {
            ekReminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date
            )
        }
        ekReminder.isCompleted = reminder.isCompleted

        try store.save(ekReminder, commit: true)
        logger.info("Wrote back reminder '\(reminder.title)' to EventKit")
    }

    // MARK: - Delete

    func delete(externalIdentifier: String, type: EKEntityType) {
        guard EKEventStore.authorizationStatus(for: type) == .fullAccess else { return }
        switch type {
        case .event:
            if let event = store.event(withIdentifier: externalIdentifier) {
                try? store.remove(event, span: .thisEvent, commit: true)
                logger.info("Deleted EKEvent \(externalIdentifier)")
            }
        case .reminder:
            if let reminder = store.calendarItem(withIdentifier: externalIdentifier) as? EKReminder {
                try? store.remove(reminder, commit: true)
                logger.info("Deleted EKReminder \(externalIdentifier)")
            }
        @unknown default:
            break
        }
    }
}
