import Foundation
import CoreLocation
import MapKit
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "travel-time")

/// Computes MapKit ETAs for upcoming located events and schedules "leave by" pre-reminders.
///
/// Usage: call `scheduleIfNeeded(for:userLocation:)` when:
///   - The app foregrounds within 6 hours of a located event.
///   - A BGProcessingTask fires (scheduled by NotificationManager every 30 min within the 6h window).
///
/// Cancellation: call `cancel(for:)` when an event is updated or deleted.
actor TravelTimePreReminder {
    private let notificationManager: NotificationManager
    /// Default buffer before computed ETA (user gets notified this many seconds before "leave now")
    private let bufferSeconds: TimeInterval = 5 * 60
    /// Track scheduled pre-reminders to avoid duplicates
    private var scheduled: Set<UUID> = []

    init(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }

    // MARK: - Public API

    /// Check the event and schedule a "leave by" notification if appropriate.
    func scheduleIfNeeded(for event: EventItem, userLocation: CLLocation) async {
        guard !scheduled.contains(event.id) else { return }
        guard case .timeBlock(let start, _) = event.anchor else { return }
        guard let coord = event.locationCoordinate else { return }

        let timeUntilEvent = start.timeIntervalSinceNow
        guard timeUntilEvent > 0, timeUntilEvent <= 6 * 3600 else { return }

        let destination = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
        ))
        let origin = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))

        let request = MKDirections.Request()
        request.source = origin
        request.destination = destination
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculateETA()
            let etaSeconds = response.expectedTravelTime
            let leaveAt = start.addingTimeInterval(-(etaSeconds + bufferSeconds))

            guard leaveAt > .now else { return }

            let notifID = "travel.\(event.id)"
            try await notificationManager.schedule(
                identifier: notifID,
                title: "Leave for \(event.title)",
                body: "Travel time is ~\(Int(etaSeconds / 60)) min. Leave in \(Int(bufferSeconds / 60)) min.",
                date: leaveAt.addingTimeInterval(-bufferSeconds),
                categoryIdentifier: NotificationCategory.event,
                userInfo: ["itemID": event.id.uuidString]
            )
            scheduled.insert(event.id)
            logger.info("Scheduled travel pre-reminder for event \(event.id) — leave at \(leaveAt)")
        } catch {
            logger.warning("ETA calculation failed for event \(event.id): \(error)")
        }
    }

    func cancel(for eventID: UUID) async {
        scheduled.remove(eventID)
        await notificationManager.cancel(identifiers: ["travel.\(eventID)"])
    }
}

// MARK: - EventItem location helper

extension EventItem {
    /// Extracts a geocoded coordinate from the event's location field.
    /// Format stored by the geocoder: "__coord:<lat>,<lon>" prefix prepended to the address.
    /// Full address (without prefix) used for display. M3 will add a dedicated coordinate field.
    var locationCoordinate: LocationTrigger.Coordinate? {
        guard let loc = location, loc.hasPrefix("__coord:") else { return nil }
        let payload = loc.dropFirst("__coord:".count)
        let firstNewline = payload.firstIndex(of: "\n") ?? payload.endIndex
        let coordStr = String(payload[..<firstNewline])
        let parts = coordStr.components(separatedBy: ",")
        guard parts.count == 2,
              let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let lon = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        return LocationTrigger.Coordinate(latitude: lat, longitude: lon)
    }
}
