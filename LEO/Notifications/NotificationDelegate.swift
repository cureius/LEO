import Foundation
import UserNotifications
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "notif-delegate")

/// NSObject shim that conforms to UNUserNotificationCenterDelegate.
/// Actors cannot inherit from NSObject, so this lives separately and bridges
/// taps/actions into the app via async tasks.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let itemRepository: ItemRepository
    private let notificationManager: NotificationManager

    init(itemRepository: ItemRepository, notificationManager: NotificationManager) {
        self.itemRepository = itemRepository
        self.notificationManager = notificationManager
    }

    // MARK: - Foreground presentation

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner + sound even when app is foreground
        completion([.banner, .sound])
    }

    // MARK: - Action handling

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completion: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let idString = userInfo["itemID"] as? String,
              let itemID = UUID(uuidString: idString) else {
            completion()
            return
        }

        let action = response.actionIdentifier
        let repo = itemRepository
        let nm = notificationManager
        let info = response.notification.request.content.userInfo
        let itemTitle = info["itemTitle"] as? String ?? ""
        let itemDueDate = (info["itemDueDate"] as? Double).map { Date(timeIntervalSince1970: $0) }

        // Use a detached task so we never inherit a stale actor context from the system.
        // Call completion() on the main thread — UNUserNotificationCenter expects it there.
        Task.detached {
            await nm.cancelAll(for: itemID)

            switch action {
            case NotificationAction.complete:
                await self.markCompleted(id: itemID, repo: repo)

            case NotificationAction.snooze10m:
                await self.snooze(id: itemID, by: 10 * 60, repo: repo, nm: nm)

            case NotificationAction.snooze1h:
                await self.snooze(id: itemID, by: 3600, repo: repo, nm: nm)

            default:
                let alert = PendingReminderAlert(id: itemID, title: itemTitle, dueDate: itemDueDate)
                await MainActor.run {
                    NotificationCenter.default.post(name: .leoReminderTapped, object: alert)
                }
            }

            await MainActor.run { completion() }
        }
    }

    // MARK: - Private action implementations

    private func markCompleted(id: UUID, repo: ItemRepository) async {
        do {
            let items = try await repo.fetch(predicate: .byID(id))
            guard var item = items.first else { return }
            item.completion = .completed(at: Date.now)
            try await repo.update(item)
            logger.info("Marked item \(id) complete via notification")
        } catch {
            logger.error("Failed to complete item \(id): \(error)")
        }
    }

    private func snooze(id: UUID, by seconds: TimeInterval,
                        repo: ItemRepository, nm: NotificationManager) async {
        do {
            let items = try await repo.fetch(predicate: .byID(id))
            guard var item = items.first else { return }
            let snoozeDate = Date.now.addingTimeInterval(seconds)
            item.anchor = .point(snoozeDate)
            try await repo.update(item)
            // Re-sync schedules a fresh burst at the new snooze time
            if let all = try? await repo.fetch() {
                await nm.sync(for: all)
            }
            logger.info("Snoozed item \(id) by \(Int(seconds))s → \(snoozeDate)")
        } catch {
            logger.error("Failed to snooze item \(id): \(error)")
        }
    }
}
