import Foundation
import UserNotifications
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "notif-delegate")

/// NSObject shim that conforms to UNUserNotificationCenterDelegate.
/// Actors cannot inherit from NSObject, so this lives separately and bridges
/// taps/actions into the app via async tasks.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let itemRepository: ItemRepository

    init(itemRepository: ItemRepository) {
        self.itemRepository = itemRepository
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

        Task {
            switch action {
            case NotificationAction.complete:
                await markCompleted(id: itemID, repo: repo)
            case NotificationAction.snooze10m:
                await snooze(id: itemID, by: 10 * 60, repo: repo)
            case NotificationAction.snooze1h:
                await snooze(id: itemID, by: 3600, repo: repo)
            default:
                break
            }
            completion()
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

    private func snooze(id: UUID, by seconds: TimeInterval, repo: ItemRepository) async {
        do {
            let items = try await repo.fetch(predicate: .byID(id))
            guard var item = items.first else { return }
            let snoozeDate = Date.now.addingTimeInterval(seconds)
            item.anchor = .point(snoozeDate)
            try await repo.update(item)
            logger.info("Snoozed item \(id) by \(Int(seconds))s")
        } catch {
            logger.error("Failed to snooze item \(id): \(error)")
        }
    }
}
