import Foundation

public struct PlannedExercise: Hashable, Sendable, Codable {
    public let exerciseID: String
    public var sets: Int
    public var reps: Int
    public var weightKg: Double?
    public var durationMin: Int?

    public init(
        exerciseID: String,
        sets: Int = 3,
        reps: Int = 10,
        weightKg: Double? = nil,
        durationMin: Int? = nil
    ) {
        self.exerciseID = exerciseID
        self.sets = sets
        self.reps = reps
        self.weightKg = weightKg
        self.durationMin = durationMin
    }
}

public struct LoggedExercise: Hashable, Sendable, Codable {
    public let exerciseID: String
    public var setsCompleted: Int
    public var repsCompleted: Int
    public var weightKg: Double?
    public var durationMin: Int?

    public init(
        exerciseID: String,
        setsCompleted: Int,
        repsCompleted: Int,
        weightKg: Double? = nil,
        durationMin: Int? = nil
    ) {
        self.exerciseID = exerciseID
        self.setsCompleted = setsCompleted
        self.repsCompleted = repsCompleted
        self.weightKg = weightKg
        self.durationMin = durationMin
    }
}

/// A time-blocked workout session.
/// Anchor: `.timeBlock(start:end:)` — the scheduled duration slot.
public struct WorkoutItem: Item {
    public let id: UUID
    public var title: String
    public var notes: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var importance: Importance
    public var anchor: Anchor
    public var completion: Completion
    public var tags: [Tag]

    public var plannedExercises: [PlannedExercise]
    public var estimatedKcal: Int
    public var actualKcal: Int?
    public var actualExercises: [LoggedExercise]?
    public var healthKitWorkoutID: String?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        importance: Importance = .normal,
        anchor: Anchor = .untimed,
        completion: Completion = .open,
        tags: [Tag] = [],
        plannedExercises: [PlannedExercise] = [],
        estimatedKcal: Int = 0,
        actualKcal: Int? = nil,
        actualExercises: [LoggedExercise]? = nil,
        healthKitWorkoutID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.importance = importance
        self.anchor = anchor
        self.completion = completion
        var t = tags
        if !t.contains(where: { $0.name == "#workout" }) {
            t.append(Tag(name: "#workout"))
        }
        self.tags = t
        self.plannedExercises = plannedExercises
        self.estimatedKcal = estimatedKcal
        self.actualKcal = actualKcal
        self.actualExercises = actualExercises
        self.healthKitWorkoutID = healthKitWorkoutID
    }

    public var displayKcal: Int { actualKcal ?? estimatedKcal }
}
