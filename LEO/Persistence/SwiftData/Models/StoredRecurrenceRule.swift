import SwiftData
import Foundation

@Model
final class StoredRecurrenceRule {
    var id: UUID
    /// RFC 5545 RRULE string.
    var raw: String
    /// Comma-separated LEORuleExtension raw values.
    var extensionsRaw: String // "" when empty

    init(id: UUID = UUID(), raw: String, extensionsRaw: String = "") {
        self.id = id
        self.raw = raw
        self.extensionsRaw = extensionsRaw
    }
}
