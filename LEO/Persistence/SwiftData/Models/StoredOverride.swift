import SwiftData
import Foundation

/// A per-occurrence override for a recurring series (skip, move, or field-only patch).
@Model
final class StoredOverride {
    var id: UUID
    /// ID of the series (StoredHabit or recurring item) this override belongs to.
    var seriesID: UUID
    /// The canonical occurrence date this override targets.
    var canonicalDate: Date
    /// JSON-encoded Override enum value.
    var overrideData: Data

    init(id: UUID = UUID(), seriesID: UUID, canonicalDate: Date, overrideData: Data) {
        self.id = id
        self.seriesID = seriesID
        self.canonicalDate = canonicalDate
        self.overrideData = overrideData
    }
}
