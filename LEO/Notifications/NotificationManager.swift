import Foundation
import UserNotifications
import OSLog

private let logger = Logger(subsystem: "com.leo.app", category: "notifications")

enum AuthorizationStatus: Sendable {
    case notDetermined, authorized, denied, provisional
}

/// All UNUserNotificationCenter interactions go through this actor.
/// Features never call UNUserNotificationCenter directly — route through here.
actor NotificationManager: NSObject {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
    }

    func requestAuthorization() async -> AuthorizationStatus {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound, .criticalAlert])
            logger.info("Notification authorization granted: \(granted)")
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

    /// Upsert a notification for a single Item. Full scheduling engine ships in M2.
    func schedule(identifier: String, title: String, body: String, date: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        try await center.add(request)
        logger.info("Scheduled notification '\(identifier)' at \(date)")
    }

    func cancel(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
    }

    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }
}
