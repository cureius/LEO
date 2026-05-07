import SwiftData
import Foundation

@Model
final class StoredTag {
    var id: UUID
    var name: String
    var colorRaw: String // TagColor.rawValue

    // Inverse relationships (optional, cascade delete not needed — tags outlive items)
    var tasks: [StoredTask]?
    var events: [StoredEvent]?
    var reminders: [StoredReminder]?
    var alarms: [StoredAlarm]?
    var habitInstances: [StoredHabitInstance]?

    init(id: UUID = UUID(), name: String, colorRaw: String = "blue") {
        self.id = id
        self.name = name
        self.colorRaw = colorRaw
    }
}
