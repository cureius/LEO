import Foundation

public enum MuscleGroup: String, Codable, CaseIterable, Hashable, Sendable {
    case chest, back, shoulders, biceps, triceps, forearms
    case quads, hamstrings, glutes, calves, core, fullBody, cardio
    var displayName: String { rawValue.capitalized }
}

public enum Equipment: String, Codable, CaseIterable, Hashable, Sendable {
    case bodyweight, dumbbells, barbell, machine, cable, band, kettlebell, pullUpBar
    var displayName: String {
        switch self {
        case .bodyweight:  "Bodyweight"
        case .dumbbells:   "Dumbbells"
        case .barbell:     "Barbell"
        case .machine:     "Machine"
        case .cable:       "Cable"
        case .band:        "Resistance band"
        case .kettlebell:  "Kettlebell"
        case .pullUpBar:   "Pull-up bar"
        }
    }
}

public enum ExerciseDifficulty: String, Codable, CaseIterable, Hashable, Sendable {
    case beginner, intermediate, advanced
    var displayName: String { rawValue.capitalized }
}

public struct Exercise: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let muscleGroups: [MuscleGroup]
    public let equipment: [Equipment]
    public let metValue: Double
    public let defaultSets: Int
    public let defaultReps: Int
    public let defaultDurationMin: Int?
    public let difficulty: ExerciseDifficulty
    public let instructions: String
    public let videoSearchQuery: String
}

// MARK: - Filter

public struct ExerciseFilter: Sendable {
    public var muscleGroups: Set<MuscleGroup>
    public var equipment: Set<Equipment>
    public var difficulty: ExerciseDifficulty?

    public init(
        muscleGroups: Set<MuscleGroup> = [],
        equipment: Set<Equipment> = [],
        difficulty: ExerciseDifficulty? = nil
    ) {
        self.muscleGroups = muscleGroups
        self.equipment = equipment
        self.difficulty = difficulty
    }

    public var isEmpty: Bool { muscleGroups.isEmpty && equipment.isEmpty && difficulty == nil }

    func matches(_ exercise: Exercise) -> Bool {
        if !muscleGroups.isEmpty && exercise.muscleGroups.allSatisfy({ !muscleGroups.contains($0) }) { return false }
        if !equipment.isEmpty && exercise.equipment.allSatisfy({ !equipment.contains($0) }) { return false }
        if let d = difficulty, exercise.difficulty != d { return false }
        return true
    }
}
