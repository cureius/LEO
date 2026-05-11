import Foundation

public enum MeasurementSource: String, Codable, Hashable, Sendable {
    case manual, healthKit
}

/// A single body-weight measurement in the time-series.
public struct BodyMeasurement: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let date: Date
    public var weightKg: Double
    public var bodyFatPct: Double?
    public var source: MeasurementSource

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        weightKg: Double,
        bodyFatPct: Double? = nil,
        source: MeasurementSource = .manual
    ) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPct = bodyFatPct
        self.source = source
    }
}
