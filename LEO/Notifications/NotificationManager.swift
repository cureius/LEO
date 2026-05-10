import Foundation
import UserNotifications
import OSLog

// MARK: - Data-change notification

extension Notification.Name {
    /// Posted on the main thread whenever items or habits are written to the local store.
    static let leoDataDidChange = Notification.Name("com.theblueman.leo.dataDidChange")
    /// Posted when user taps a reminder/alarm notification body (not an action button).
    /// object: PendingReminderAlert
    static let leoReminderTapped = Notification.Name("com.theblueman.leo.reminderTapped")
}

// MARK: - In-app reminder alert model

struct PendingReminderAlert: Identifiable, Sendable {
    let id: UUID          // itemID
    let title: String
    let dueDate: Date?
}

private let logger = Logger(subsystem: "com.theblueman.leo", category: "notifications")

// MARK: - Authorization status

enum AuthorizationStatus: Sendable {
    case notDetermined, authorized, denied, provisional
}

// MARK: - Notification categories / actions

enum NotificationCategory {
    static let reminder = "LEO_REMINDER"
    static let alarm    = "LEO_ALARM"
    static let event    = "LEO_EVENT"
}

enum NotificationAction {
    static let complete  = "COMPLETE"
    static let snooze10m = "SNOOZE_10M"
    static let snooze1h  = "SNOOZE_1H"
    static let open      = "OPEN"
}

// MARK: - NotificationManager

/// All UNUserNotificationCenter interactions route through this actor.
/// Features never call UNUserNotificationCenter directly.
///
/// iOS caps pending notifications at ~64. We manage a sliding 30-day window for recurring items:
/// a BGAppRefreshTask fires daily to top up expiring slots.
actor NotificationManager {
    nonisolated let center = UNUserNotificationCenter.current()

    init() {
        logger.info("NotificationManager initialized")
    }

    // MARK: - Authorization

    func requestAuthorization() async -> AuthorizationStatus {
        do {
            // .timeSensitive lets notifications break through Focus modes (requires entitlement)
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound, .timeSensitive])
            logger.info("Notification authorization granted: \(granted)")
            if granted { registerCategories() }
            return granted ? .authorized : .denied
        } catch {
            logger.error("Notification auth error: \(error)")
            return .denied
        }
    }

    func currentAuthorizationStatus() async -> AuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .ephemeral: return .authorized
        case .denied:                 return .denied
        case .provisional:            return .provisional
        case .notDetermined:          return .notDetermined
        @unknown default:             return .notDetermined
        }
    }

    // MARK: - Sync

    /// Diff-then-patch: schedule any missing requests, remove any stale ones.
    /// For recurring items, expands the next 30 days via RecurrenceEngine.
    func sync(for items: [any Item]) async {
        let desired = await buildDesiredRequests(for: items)
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = Set(pending.map(\.identifier))
        let desiredIDs = Set(desired.map(\.identifier))

        // Remove stale
        let toRemove = pendingIDs.subtracting(desiredIDs)
        if !toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(toRemove))
            logger.info("Removed \(toRemove.count) stale notifications")
        }

        // Add missing
        let toAdd = desired.filter { !pendingIDs.contains($0.identifier) }
        for request in toAdd {
            do {
                try await center.add(request)
            } catch {
                logger.error("Failed to schedule \(request.identifier): \(error)")
            }
        }
        if !toAdd.isEmpty {
            logger.info("Scheduled \(toAdd.count) new notifications")
        }
    }

    // MARK: - Direct schedule

    func schedule(identifier: String, title: String, body: String, date: Date,
                  categoryIdentifier: String = NotificationCategory.reminder,
                  userInfo: [AnyHashable: Any] = [:]) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = Self.alarmSound
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = userInfo
        content.interruptionLevel = .timeSensitive

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
        logger.info("Scheduled '\(identifier)' at \(date)")
    }

    // MARK: - Cancel

    func cancel(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        logger.info("Cancelled \(identifiers.count) notifications")
    }

    func cancelAll(for itemID: UUID) async {
        let pending = await center.pendingNotificationRequests()
        let prefix = "item.\(itemID)"
        let ids = pending.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
        logger.info("Cancelled all pending notifications")
    }

    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }

    // MARK: - Private: request builder

    // Dense burst: every 1 min for 20 min, then every 5 min up to 60 min
    // Gives "keeps ringing" behaviour without Critical Alerts entitlement
    private var burstOffsets: [TimeInterval] {
        var offsets: [TimeInterval] = []
        // Every 60 s for first 20 min
        for m in 1...20 { offsets.append(TimeInterval(m * 60)) }
        // Every 5 min from 25–60 min
        for m in stride(from: 25, through: 60, by: 5) { offsets.append(TimeInterval(m * 60)) }
        return offsets
    }

    private func buildDesiredRequests(for items: [any Item]) async -> [UNNotificationRequest] {
        let horizon = Date.now.addingTimeInterval(30 * 86400)
        var requests: [UNNotificationRequest] = []

        for item in items where !item.isCompleted {
            let dates = firingDates(for: item, upTo: horizon)

            // Burst for ANY item with a point/due anchor — not just ReminderItem/AlarmItem.
            // Users set timed reminders as TaskItems too (QuickAdd fallback).
            let needsBurst: Bool
            switch item.anchor {
            case .point, .dueAt: needsBurst = true
            default:             needsBurst = false
            }

            for date in dates {
                guard date > .now else { continue }

                requests.append(makeRequest(for: item, at: date, suffix: "primary"))

                if needsBurst {
                    for (idx, offset) in burstOffsets.enumerated() {
                        let burstDate = date.addingTimeInterval(offset)
                        guard burstDate > .now, burstDate <= horizon else { continue }
                        requests.append(makeRequest(for: item, at: burstDate,
                                                    suffix: "burst.\(idx + 1)",
                                                    isFollowUp: true))
                    }
                }
            }
            if requests.count >= 60 { break }
        }

        logger.info("Built \(requests.count) notification requests for \(items.count) items")
        return requests
    }

    private func firingDates(for item: any Item, upTo horizon: Date) -> [Date] {
        switch item.anchor {
        case .point(let d):
            return d <= horizon ? [d] : []
        case .dueAt(let d):
            return d <= horizon ? [d] : []
        case .timeBlock(let start, _):
            return start <= horizon ? [start] : []
        default:
            return []
        }
    }

    private static let alarmSound = UNNotificationSound(named: UNNotificationSoundName("leo_alarm.caf"))

    private func makeRequest(for item: any Item, at date: Date,
                             suffix: String, isFollowUp: Bool = false) -> UNNotificationRequest {
        // Use alarm sound + time-sensitive level for any timed point/due-date item
        let isTimed: Bool
        switch item.anchor {
        case .point, .dueAt: isTimed = true
        default:             isTimed = false
        }

        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = isFollowUp
            ? "Still waiting — tap Done or Snooze."
            : (item.notes.flatMap { $0.isEmpty ? nil : $0 } ?? "Tap to take action.")
        content.sound = isTimed ? Self.alarmSound : .default
        content.userInfo = [
            "itemID": item.id.uuidString,
            "itemTitle": item.title,
            "itemDueDate": date.timeIntervalSince1970
        ]
        content.categoryIdentifier = categoryID(for: item)
        content.interruptionLevel = isTimed ? .timeSensitive : .active

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let id = "item.\(item.id).\(suffix)"
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    private func categoryID(for item: any Item) -> String {
        switch item {
        case is AlarmItem:    return NotificationCategory.alarm
        case is ReminderItem: return NotificationCategory.reminder
        case is EventItem:    return NotificationCategory.event
        default:              return NotificationCategory.reminder
        }
    }

    // MARK: - Categories

    private func registerCategories() {
        let completeAction = UNNotificationAction(
            identifier: NotificationAction.complete,
            title: "Complete",
            options: [.authenticationRequired]
        )
        let snooze10 = UNNotificationAction(
            identifier: NotificationAction.snooze10m,
            title: "Snooze 10 min",
            options: []
        )
        let snooze1h = UNNotificationAction(
            identifier: NotificationAction.snooze1h,
            title: "Snooze 1 hour",
            options: []
        )

        let reminderCategory = UNNotificationCategory(
            identifier: NotificationCategory.reminder,
            actions: [completeAction, snooze10, snooze1h],
            intentIdentifiers: [],
            options: []
        )
        let eventCategory = UNNotificationCategory(
            identifier: NotificationCategory.event,
            actions: [snooze10, snooze1h],
            intentIdentifiers: [],
            options: []
        )
        let alarmCategory = UNNotificationCategory(
            identifier: NotificationCategory.alarm,
            actions: [completeAction, snooze10],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([reminderCategory, eventCategory, alarmCategory])
    }
}
