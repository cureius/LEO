import EventKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "eventkit")

// MARK: - Sync report

struct EKSyncReport: Sendable {
    var imported: Int = 0
    var updated: Int = 0
    var removed: Int = 0
}

// MARK: - EventKitBridge

/// Imports iOS calendar events and reminders into LEO's SwiftData store.
/// LEO is always the consumer — EventKit is the source of truth for these items.
/// Write-back (M3-T02) is a separate layer on top of this read bridge.
actor EventKitBridge {
    private let store = EKEventStore()
    private let itemRepository: ItemRepository
    /// Calendar and reminder list identifiers the user has subscribed in settings
    private var subscribedCalendarIDs: Set<String> = []
    private var subscribedReminderListIDs: Set<String> = []
    /// How far forward/back we import (bounded to avoid calendar history pollution)
    private let importWindow: TimeInterval = 30 * 86400

    init(itemRepository: ItemRepository) {
        self.itemRepository = itemRepository
    }

    // MARK: - Authorization

    func requestEventsAccess() async -> EKAuthorizationStatus {
        guard EKEventStore.authorizationStatus(for: .event) != .fullAccess else {
            return .fullAccess
        }
        do {
            try await store.requestFullAccessToEvents()
            logger.info("EventKit events access granted")
            return EKEventStore.authorizationStatus(for: .event)
        } catch {
            logger.warning("EventKit events access denied: \(error)")
            return .denied
        }
    }

    func requestRemindersAccess() async -> EKAuthorizationStatus {
        guard EKEventStore.authorizationStatus(for: .reminder) != .fullAccess else {
            return .fullAccess
        }
        do {
            try await store.requestFullAccessToReminders()
            logger.info("EventKit reminders access granted")
            return EKEventStore.authorizationStatus(for: .reminder)
        } catch {
            logger.warning("EventKit reminders access denied: \(error)")
            return .denied
        }
    }

    // MARK: - Available sources

    func availableCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
    }

    func availableReminderLists() -> [EKCalendar] {
        store.calendars(for: .reminder)
    }

    /// Calendars grouped by their EKSource (one row per Google account / iCloud / Exchange / local).
    /// Sorted so iCloud comes first, then external accounts alphabetically.
    func calendarsGroupedBySource() -> [(source: EKSource, calendars: [EKCalendar])] {
        let calendars = store.calendars(for: .event)
        let grouped = Dictionary(grouping: calendars, by: { $0.source.sourceIdentifier })
        return grouped
            .compactMap { (_, cals) -> (EKSource, [EKCalendar])? in
                guard let first = cals.first else { return nil }
                let sorted = cals.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
                return (first.source, sorted)
            }
            .sorted { lhs, rhs in
                // iCloud first, then by source title
                if lhs.0.sourceType == .calDAV && lhs.0.title.localizedCaseInsensitiveContains("icloud") { return true }
                if rhs.0.sourceType == .calDAV && rhs.0.title.localizedCaseInsensitiveContains("icloud") { return false }
                return lhs.0.title.localizedCompare(rhs.0.title) == .orderedAscending
            }
    }

    /// Asks iOS to pull the latest from remote sources (CalDAV/Exchange) before we re-read.
    /// Safe to call frequently — iOS rate-limits internally.
    func refreshSources() async {
        store.refreshSourcesIfNecessary()
    }

    /// The current subscription set — used by callers that want to drive sync without re-reading UserDefaults.
    var subscribedCalendars: Set<String> { subscribedCalendarIDs }
    var subscribedReminderLists: Set<String> { subscribedReminderListIDs }

    // MARK: - Subscription management

    func subscribe(calendarIDs: Set<String>, reminderListIDs: Set<String>) {
        subscribedCalendarIDs = calendarIDs
        subscribedReminderListIDs = reminderListIDs
    }

    // MARK: - Sync

    func sync() async throws -> EKSyncReport {
        // Reset the store's in-memory cache so we read the latest data from
        // the system calendar database. Required after EKEventStoreChanged fires;
        // without this the store returns stale objects it has already loaded.
        store.reset()
        // Yield once so the actor's cooperative thread can process any pending
        // EventKit internal callbacks before we issue queries against the store.
        await Task.yield()

        var report = EKSyncReport()

        // Sync events
        let eventReport = try await syncEvents()
        report.imported += eventReport.imported
        report.updated  += eventReport.updated
        report.removed  += eventReport.removed

        // Sync reminders
        let reminderReport = try await syncReminders()
        report.imported += reminderReport.imported
        report.updated  += reminderReport.updated
        report.removed  += reminderReport.removed

        logger.info("EKSync done: +\(report.imported) ~\(report.updated) -\(report.removed)")
        return report
    }

    // MARK: - Private: event sync

    private func syncEvents() async throws -> EKSyncReport {
        var report = EKSyncReport()
        guard !subscribedCalendarIDs.isEmpty else { return report }

        let calendars = availableCalendars().filter { subscribedCalendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return report }

        let now = Date.now
        let start = now.addingTimeInterval(-importWindow)
        let end = now.addingTimeInterval(importWindow)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let ekEvents = store.events(matching: predicate)

        let existingItems = try await itemRepository.fetch()
        let existingExternalIDs = Set(existingItems.compactMap { ($0 as? EventItem)?.externalRef?.identifier })

        let existingEventItems = existingItems.compactMap { $0 as? EventItem }
        for ekEvent in ekEvents {
            let eid = ekEvent.eventIdentifier ?? ""
            if existingExternalIDs.contains(eid) {
                // EventKit is source of truth — always overwrite scheduling data.
                // Preserve LEO-only fields: id, createdAt, importance, completion, tags.
                if let existing = existingEventItems.first(where: { $0.externalRef?.identifier == eid }) {
                    let fromEK = EventItem(from: ekEvent)
                    let updatedAt = ekEvent.lastModifiedDate ?? existing.updatedAt
                    let merged = EventItem(
                        id: existing.id, title: fromEK.title, notes: fromEK.notes,
                        createdAt: existing.createdAt, updatedAt: updatedAt,
                        importance: existing.importance, anchor: fromEK.anchor,
                        completion: existing.completion, tags: existing.tags,
                        location: fromEK.location, attendees: fromEK.attendees,
                        externalRef: fromEK.externalRef
                    )
                    // Skip write if nothing changed (title + anchor are the likely diffs)
                    if merged.title != existing.title
                        || merged.anchor != existing.anchor
                        || merged.location != existing.location
                        || merged.notes != existing.notes {
                        try await itemRepository.update(merged)
                        report.updated += 1
                    }
                }
            } else {
                let item = EventItem(from: ekEvent)
                try await itemRepository.add(item)
                report.imported += 1
            }
        }

        // Remove items whose external events no longer exist
        let activeEKIDs = Set(ekEvents.compactMap(\.eventIdentifier))
        let toRemove = existingItems.compactMap { $0 as? EventItem }
            .filter { item -> Bool in
                guard let ref = item.externalRef, ref.source == .eventKit else { return false }
                return subscribedCalendarIDs.contains(where: { _ in true }) && !activeEKIDs.contains(ref.identifier)
            }
        for item in toRemove {
            try await itemRepository.delete(id: item.id)
            report.removed += 1
        }

        return report
    }

    // MARK: - Private: reminder sync

    private func syncReminders() async throws -> EKSyncReport {
        var report = EKSyncReport()
        guard !subscribedReminderListIDs.isEmpty else { return report }

        let lists = availableReminderLists().filter { subscribedReminderListIDs.contains($0.calendarIdentifier) }
        guard !lists.isEmpty else { return report }

        let predicate = store.predicateForReminders(in: lists)
        let ekReminders = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[EKReminder], Error>) in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }

        let existingItems = try await itemRepository.fetch()
        let existingExternalIDs = Set(existingItems.compactMap { ($0 as? ReminderItem)?.externalRef?.identifier })

        for ekReminder in ekReminders where !ekReminder.isCompleted {
            let eid = ekReminder.calendarItemIdentifier
            if !existingExternalIDs.contains(eid) {
                let item = ReminderItem(from: ekReminder)
                try await itemRepository.add(item)
                report.imported += 1
            }
        }

        return report
    }
}

// MARK: - EKEvent → EventItem

extension EventItem {
    init(from ekEvent: EKEvent) {
        let anchor: Anchor
        if let start = ekEvent.startDate, let end = ekEvent.endDate {
            anchor = .timeBlock(start: start, end: end)
        } else {
            anchor = .untimed
        }
        self.init(
            title: ekEvent.title ?? "Untitled",
            notes: ekEvent.notes,
            anchor: anchor,
            location: ekEvent.location,
            attendees: ekEvent.attendees?.compactMap { $0.name } ?? [],
            externalRef: ExternalRef(source: .eventKit, identifier: ekEvent.eventIdentifier ?? UUID().uuidString)
        )
    }
}

// MARK: - EKReminder → ReminderItem

extension ReminderItem {
    init(from ekReminder: EKReminder) {
        let anchor: Anchor
        if let comps = ekReminder.dueDateComponents, let date = Calendar.current.date(from: comps) {
            anchor = .point(date)
        } else {
            anchor = .untimed
        }
        self.init(
            title: ekReminder.title ?? "Reminder",
            notes: ekReminder.notes,
            anchor: anchor,
            externalRef: ExternalRef(source: .eventKit, identifier: ekReminder.calendarItemIdentifier)
        )
    }
}
