import Foundation

struct GetBodyProfileTool: LEOTool {
    struct Input: Decodable, Sendable {}

    struct Output: Encodable, Sendable {
        let hasProfile: Bool
        let heightCm: Double?
        let weightKg: Double?
        let ageYears: Int?
        let sex: String?
        let activityLevel: String?
        let goalPhysique: String?
        let goalWeightKg: Double?
        let dietType: String?
        let allergies: [String]
        let medicalFlags: [String]
        let bmi: Double?
        let bmr: Double?
        let tdee: Double?
        let dailyKcalTarget: Double?
        let aggressiveGoalWarning: String?
        let recentMeasurements: [MeasurementOutput]

        struct MeasurementOutput: Encodable, Sendable {
            let date: String
            let weightKg: Double
            let bodyFatPct: Double?
        }
    }

    let definition = ToolDefinition(
        name: "get_body_profile",
        description: "Get the user's body profile, computed fitness stats (BMI/BMR/TDEE/daily kcal target), and recent weight measurements. Always call this before generating any fitness plan.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([:]),
            "required": .array([])
        ]
    )

    private let bodyProfileRepository: BodyProfileRepository

    init(bodyProfileRepository: BodyProfileRepository) {
        self.bodyProfileRepository = bodyProfileRepository
    }

    func run(_ input: Input, context: ToolContext) async throws -> Output {
        guard let profile = await bodyProfileRepository.load() else {
            return Output(
                hasProfile: false, heightCm: nil, weightKg: nil, ageYears: nil,
                sex: nil, activityLevel: nil, goalPhysique: nil, goalWeightKg: nil,
                dietType: nil, allergies: [], medicalFlags: [],
                bmi: nil, bmr: nil, tdee: nil, dailyKcalTarget: nil,
                aggressiveGoalWarning: nil, recentMeasurements: []
            )
        }
        let kcalResult = BodyMath.dailyKcalTarget(profile: profile)
        let measurements = await bodyProfileRepository.recentMeasurements(limit: 10)
        let iso = ISO8601DateFormatter()
        return Output(
            hasProfile: true,
            heightCm: profile.heightCm,
            weightKg: profile.weightKg,
            ageYears: profile.ageYears,
            sex: profile.sex.rawValue,
            activityLevel: profile.activityLevel.rawValue,
            goalPhysique: profile.goalPhysique.rawValue,
            goalWeightKg: profile.goalWeightKg,
            dietType: profile.dietType.rawValue,
            allergies: profile.allergies,
            medicalFlags: profile.medicalFlags.map(\.rawValue),
            bmi: kcalResult.bmi,
            bmr: kcalResult.bmr,
            tdee: kcalResult.tdee,
            dailyKcalTarget: kcalResult.dailyKcal,
            aggressiveGoalWarning: kcalResult.aggressiveGoalWarning,
            recentMeasurements: measurements.map { m in
                Output.MeasurementOutput(
                    date: iso.string(from: m.date),
                    weightKg: m.weightKg,
                    bodyFatPct: m.bodyFatPct
                )
            }
        )
    }
}
