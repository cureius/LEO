import Foundation

/// A geographic trigger for location-based reminders. Uses plain lat/lon so Domain stays CoreLocation-free.
public struct LocationTrigger: Hashable, Sendable, Codable {
    public struct Coordinate: Hashable, Sendable, Codable {
        public let latitude: Double
        public let longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public enum TriggerDirection: String, Hashable, Sendable, Codable {
        case entering, leaving
    }

    public let coordinate: Coordinate
    public let radiusMeters: Double
    public let direction: TriggerDirection

    public init(coordinate: Coordinate, radiusMeters: Double = 100, direction: TriggerDirection = .entering) {
        self.coordinate = coordinate
        self.radiusMeters = max(100, radiusMeters) // iOS minimum region radius
        self.direction = direction
    }
}
