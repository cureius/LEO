import Foundation
import CoreLocation
import UserNotifications
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "location-reminders")

/// Manages CLLocationManager region monitoring for location-anchored Items.
///
/// iOS hard limits:
///  - 20 monitored regions per app
///  - 100m minimum region radius
///
/// Strategy: monitor the nearest 20 undelivered location-anchored items by priority.
/// On each sync call, we re-rank and swap out regions as needed.
final class LocationReminderManager: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let notificationManager: NotificationManager
    /// itemID → region identifier mapping for the currently monitored set
    private var monitored: [UUID: String] = [:]

    init(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Authorization

    func requestWhenInUsePermission() {
        let status = locationManager.authorizationStatus
        guard status == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysPermission() {
        let status = locationManager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .notDetermined else { return }
        locationManager.requestAlwaysAuthorization()
    }

    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    // MARK: - Sync

    /// Update monitored regions to match the current set of location-anchored items.
    /// Call after any item add/delete/complete, and on app foreground.
    func sync(items: [any Item]) {
        let locationItems = items.filter { item -> Bool in
            if case .location = item.anchor { return !item.isCompleted }
            return false
        }

        // Stop monitoring items no longer in the list
        let activeIDs = Set(locationItems.map(\.id))
        for (itemID, regionID) in monitored where !activeIDs.contains(itemID) {
            let region = locationManager.monitoredRegions.first { $0.identifier == regionID }
            if let region { locationManager.stopMonitoring(for: region) }
            monitored.removeValue(forKey: itemID)
        }

        // Start monitoring new items (up to iOS 20-region cap)
        let slots = 20 - locationManager.monitoredRegions.count
        let newItems = locationItems.filter { monitored[$0.id] == nil }.prefix(max(0, slots))
        for item in newItems {
            guard case .location(let trigger) = item.anchor else { continue }
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(
                    latitude: trigger.coordinate.latitude,
                    longitude: trigger.coordinate.longitude
                ),
                radius: trigger.radiusMeters,
                identifier: "leo.location.\(item.id)"
            )
            region.notifyOnEntry = (trigger.direction == .entering)
            region.notifyOnExit  = (trigger.direction == .leaving)
            locationManager.startMonitoring(for: region)
            monitored[item.id] = region.identifier
            logger.info("Started monitoring region for item \(item.id)")
        }
    }

    func stopAll() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        monitored.removeAll()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in await handleRegionEvent(region, entered: true) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in await handleRegionEvent(region, entered: false) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        logger.error("Region monitoring failed: \(error)")
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        logger.info("Location authorization changed: \(status.rawValue)")
    }

    // MARK: - Private

    private func handleRegionEvent(_ region: CLRegion, entered: Bool) async {
        guard let itemID = monitored.first(where: { $0.value == region.identifier })?.key else { return }
        let direction = entered ? "entered" : "exited"
        logger.info("Region \(direction) for item \(itemID)")

        let id = "location.\(itemID).\(Date.now.timeIntervalSince1970)"
        try? await notificationManager.schedule(
            identifier: id,
            title: "Location reminder",
            body: "You \(direction) your saved location.",
            date: .now.addingTimeInterval(1),
            userInfo: ["itemID": itemID.uuidString]
        )
    }
}
