import SwiftData
import Foundation

/// Single-row store for the user's body profile.
/// Query: `FetchDescriptor<StoredBodyProfile>(fetchLimit: 1)`.
@Model
final class StoredBodyProfile {
    var heightCm: Double
    var weightKg: Double
    var sexRaw: String
    var birthDate: Date
    var bodyFatPct: Double?
    var activityLevelRaw: String
    var goalWeightKg: Double?
    var goalPhysiqueRaw: String
    var targetDate: Date?
    var dietTypeRaw: String
    // Arrays stored as JSON Data (CloudKit constraint)
    var allergiesData: Data
    var intolerancesData: Data
    var medicalFlagsData: Data
    var unitPreferenceRaw: String

    init(
        heightCm: Double = 170,
        weightKg: Double = 70,
        sexRaw: String = "other",
        birthDate: Date = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now,
        bodyFatPct: Double? = nil,
        activityLevelRaw: String = "moderate",
        goalWeightKg: Double? = nil,
        goalPhysiqueRaw: String = "maintain",
        targetDate: Date? = nil,
        dietTypeRaw: String = "omnivore",
        allergiesData: Data = "[]".data(using: .utf8)!,
        intolerancesData: Data = "[]".data(using: .utf8)!,
        medicalFlagsData: Data = "[]".data(using: .utf8)!,
        unitPreferenceRaw: String = "metric"
    ) {
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.sexRaw = sexRaw
        self.birthDate = birthDate
        self.bodyFatPct = bodyFatPct
        self.activityLevelRaw = activityLevelRaw
        self.goalWeightKg = goalWeightKg
        self.goalPhysiqueRaw = goalPhysiqueRaw
        self.targetDate = targetDate
        self.dietTypeRaw = dietTypeRaw
        self.allergiesData = allergiesData
        self.intolerancesData = intolerancesData
        self.medicalFlagsData = medicalFlagsData
        self.unitPreferenceRaw = unitPreferenceRaw
    }
}
