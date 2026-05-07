import SwiftData
import Foundation

@Model
final class StoredHabit {
    var id: UUID
    var name: String
    var frequencyData: Data     // JSON-encoded HabitFrequency
    var timeHintData: Data?     // JSON-encoded TimeOfDay?
    var targetDurationSeconds: Double?
    var forgivenessData: Data   // JSON-encoded HabitForgiveness
    var createdAt: Date
    var isArchived: Bool

    @Relationship(deleteRule: .cascade)
    var instances: [StoredHabitInstance]?

    var recurrenceRule: StoredRecurrenceRule?

    init(
        id: UUID = UUID(),
        name: String,
        frequencyData: Data,
        timeHintData: Data? = nil,
        targetDurationSeconds: Double? = nil,
        forgivenessData: Data,
        createdAt: Date = .now,
        isArchived: Bool = false,
        recurrenceRule: StoredRecurrenceRule? = nil
    ) {
        self.id = id
        self.name = name
        self.frequencyData = frequencyData
        self.timeHintData = timeHintData
        self.targetDurationSeconds = targetDurationSeconds
        self.forgivenessData = forgivenessData
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.recurrenceRule = recurrenceRule
    }
}
