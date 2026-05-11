import SwiftData
import Foundation

@Model
final class StoredMeasurement {
    var id: UUID
    var date: Date
    var weightKg: Double
    var bodyFatPct: Double?
    var sourceRaw: String

    init(
        id: UUID = UUID(),
        date: Date = .now,
        weightKg: Double,
        bodyFatPct: Double? = nil,
        sourceRaw: String = "manual"
    ) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPct = bodyFatPct
        self.sourceRaw = sourceRaw
    }
}
