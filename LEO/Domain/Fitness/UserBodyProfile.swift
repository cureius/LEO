import Foundation

// MARK: - Enumerations

public enum BiologicalSex: String, Codable, CaseIterable, Hashable, Sendable {
    case male, female, other
    var displayName: String {
        switch self { case .male: "Male"; case .female: "Female"; case .other: "Other" }
    }
}

public enum ActivityLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case sedentary, light, moderate, active, veryActive
    var displayName: String {
        switch self {
        case .sedentary:  "Sedentary (little/no exercise)"
        case .light:      "Lightly active (1–3 days/week)"
        case .moderate:   "Moderately active (3–5 days/week)"
        case .active:     "Active (6–7 days/week)"
        case .veryActive: "Very active (athlete/physical job)"
        }
    }
    var factor: Double {
        switch self {
        case .sedentary:  1.2
        case .light:      1.375
        case .moderate:   1.55
        case .active:     1.725
        case .veryActive: 1.9
        }
    }
}

public enum GoalPhysique: String, Codable, CaseIterable, Hashable, Sendable {
    case lean, athletic, muscular, maintain
    var displayName: String {
        switch self { case .lean: "Lean"; case .athletic: "Athletic"; case .muscular: "Muscular"; case .maintain: "Maintain" }
    }
}

public enum DietType: String, Codable, CaseIterable, Hashable, Sendable {
    case omnivore, vegetarian, vegan, pescatarian, keto, paleo, mediterranean, halal, kosher, custom
    var displayName: String { rawValue.capitalized }
}

public enum MedicalFlag: String, Codable, CaseIterable, Hashable, Sendable {
    case pregnant, heartCondition, diabetic, other
    var displayName: String {
        switch self {
        case .pregnant:       "Pregnant"
        case .heartCondition: "Heart condition"
        case .diabetic:       "Diabetic"
        case .other:          "Other condition"
        }
    }
}

public enum UnitPreference: String, Codable, CaseIterable, Hashable, Sendable {
    case metric, imperial
    var displayName: String { rawValue.capitalized }
}

// MARK: - UserBodyProfile

/// The user's body profile for fitness planning and calorie math.
/// All measurements are stored in SI units (kg, cm) regardless of display preference.
public struct UserBodyProfile: Hashable, Sendable, Codable {
    // Body metrics
    public var heightCm: Double
    public var weightKg: Double
    public var sex: BiologicalSex
    public var birthDate: Date
    public var bodyFatPct: Double?
    public var activityLevel: ActivityLevel

    // Goals
    public var goalWeightKg: Double?
    public var goalPhysique: GoalPhysique
    public var targetDate: Date?

    // Diet
    public var dietType: DietType
    public var allergies: [String]
    public var intolerances: [String]
    public var medicalFlags: [MedicalFlag]

    // Display
    public var unitPreference: UnitPreference

    public init(
        heightCm: Double = 170,
        weightKg: Double = 70,
        sex: BiologicalSex = .other,
        birthDate: Date = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now,
        bodyFatPct: Double? = nil,
        activityLevel: ActivityLevel = .moderate,
        goalWeightKg: Double? = nil,
        goalPhysique: GoalPhysique = .maintain,
        targetDate: Date? = nil,
        dietType: DietType = .omnivore,
        allergies: [String] = [],
        intolerances: [String] = [],
        medicalFlags: [MedicalFlag] = [],
        unitPreference: UnitPreference = .metric
    ) {
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.sex = sex
        self.birthDate = birthDate
        self.bodyFatPct = bodyFatPct
        self.activityLevel = activityLevel
        self.goalWeightKg = goalWeightKg
        self.goalPhysique = goalPhysique
        self.targetDate = targetDate
        self.dietType = dietType
        self.allergies = allergies
        self.intolerances = intolerances
        self.medicalFlags = medicalFlags
        self.unitPreference = unitPreference
    }

    // MARK: - Computed

    var ageYears: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 0
    }

    var heightFt: Double { heightCm / 30.48 }
    var weightLb: Double { weightKg * 2.20462 }
}
