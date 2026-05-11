import Testing
@testable import LEO
import Foundation

/// Validates Mifflin–St Jeor BMR formula and derived metrics.
@Suite("BodyMath")
struct BodyMathTests {

    // MARK: - Fixtures

    // 25yo male, 80kg, 180cm, moderate
    static let maleProfile = makeProfile(weightKg: 80, heightCm: 180, sex: .male, ageYears: 25, activity: .moderate)
    // 30yo female, 60kg, 165cm, light
    static let femaleProfile = makeProfile(weightKg: 60, heightCm: 165, sex: .female, ageYears: 30, activity: .light)
    // 35yo other, 70kg, 170cm, active
    static let otherProfile = makeProfile(weightKg: 70, heightCm: 170, sex: .other, ageYears: 35, activity: .active)

    // MARK: - BMI

    @Test("BMI: 80kg / 180cm → ~24.7")
    func testBMIMale() {
        let bmi = BodyMath.bmi(weightKg: 80, heightCm: 180)
        #expect(abs(bmi - 24.69) < 0.1)
    }

    @Test("BMI: 60kg / 165cm → ~22.0")
    func testBMIFemale() {
        let bmi = BodyMath.bmi(weightKg: 60, heightCm: 165)
        #expect(abs(bmi - 22.04) < 0.1)
    }

    @Test("BMI: zero height returns 0")
    func testBMIZeroHeight() {
        let bmi = BodyMath.bmi(weightKg: 70, heightCm: 0)
        #expect(bmi == 0)
    }

    // MARK: - BMR (Mifflin–St Jeor)

    @Test("BMR male: 80kg/180cm/25yo → ~1880")
    func testBMRMale() {
        let bmr = BodyMath.bmr(profile: Self.maleProfile)
        // Mifflin-St Jeor male: 10*80 + 6.25*180 - 5*25 + 5 = 800 + 1125 - 125 + 5 = 1805
        #expect(abs(bmr - 1805) < 5)
    }

    @Test("BMR female: 60kg/165cm/30yo → ~1342")
    func testBMRFemale() {
        let bmr = BodyMath.bmr(profile: Self.femaleProfile)
        // 10*60 + 6.25*165 - 5*30 - 161 = 600 + 1031.25 - 150 - 161 = 1320.25
        #expect(abs(bmr - 1320) < 5)
    }

    @Test("BMR for 'other' sex is between male and female")
    func testBMROther() {
        let bmrOther = BodyMath.bmr(profile: BodyMathTests.otherProfile)
        var maleP = BodyMathTests.otherProfile; maleP.sex = .male
        var femaleP = BodyMathTests.otherProfile; femaleP.sex = .female
        let bmrMale = BodyMath.bmr(profile: maleP)
        let bmrFemale = BodyMath.bmr(profile: femaleP)
        #expect(bmrOther > bmrFemale && bmrOther < bmrMale)
    }

    // MARK: - TDEE

    @Test("TDEE = BMR × 1.55 for moderate activity")
    func testTDEEModerate() {
        let bmr = BodyMath.bmr(profile: BodyMathTests.maleProfile)
        let tdee = BodyMath.tdee(profile: BodyMathTests.maleProfile)
        #expect(abs(tdee - bmr * 1.55) < 1)
    }

    @Test("Activity factors: sedentary < light < moderate < active < very active")
    func testActivityFactorOrder() {
        var p = BodyMathTests.maleProfile
        let levels: [ActivityLevel] = [.sedentary, .light, .moderate, .active, .veryActive]
        var tdees: [Double] = []
        for level in levels {
            p.activityLevel = level
            tdees.append(BodyMath.tdee(profile: p))
        }
        for i in 0..<(tdees.count - 1) {
            #expect(tdees[i] < tdees[i + 1])
        }
    }

    // MARK: - Daily kcal target

    @Test("No goal weight: target == TDEE")
    func testTargetNoGoal() {
        var p = BodyMathTests.maleProfile
        p.goalWeightKg = nil
        p.targetDate = nil
        let result = BodyMath.dailyKcalTarget(profile: p)
        let tdee = BodyMath.tdee(profile: p)
        #expect(abs(result.dailyKcal - tdee) < 1)
    }

    @Test("Aggressive goal triggers warning and caps deficit at 20% of TDEE")
    func testAggressiveGoalWarning() {
        var p = BodyMathTests.maleProfile
        p.goalWeightKg = 60  // lose 20 kg
        p.targetDate = Calendar.current.date(byAdding: .month, value: 1, to: .now)
        let result = BodyMath.dailyKcalTarget(profile: p)
        #expect(result.aggressiveGoalWarning != nil)
        let tdee = BodyMath.tdee(profile: p)
        let maxDeficit = tdee * 0.20
        #expect(result.dailyKcal >= tdee - maxDeficit - 1)
    }

    @Test("Minimum daily kcal is 1200")
    func testMinimumKcal() {
        var p = BodyMathTests.makeProfile(weightKg: 45, heightCm: 155, sex: .female, ageYears: 60, activity: .sedentary)
        p.goalWeightKg = 30
        p.targetDate = Calendar.current.date(byAdding: .month, value: 1, to: .now)
        let result = BodyMath.dailyKcalTarget(profile: p)
        #expect(result.dailyKcal >= 1200)
    }

    // MARK: - Per-exercise kcal

    @Test("kcalBurned: MET 8, 30 min, 80 kg → expected range")
    func testKcalBurned() {
        let kcal = BodyMath.kcalBurned(metValue: 8.0, durationMin: 30, weightKg: 80)
        // (8 * 80 * 3.5 / 200) * 30 = (2240/200) * 30 = 11.2 * 30 = 336
        #expect(abs(kcal - 336) < 5)
    }

    @Test("kcalBurned scales proportionally with duration")
    func testKcalBurnedScaling() {
        let kcal30 = BodyMath.kcalBurned(metValue: 5.0, durationMin: 30, weightKg: 70)
        let kcal60 = BodyMath.kcalBurned(metValue: 5.0, durationMin: 60, weightKg: 70)
        #expect(abs(kcal60 - kcal30 * 2) < 1)
    }

    // MARK: - Helpers

    static func makeProfile(
        weightKg: Double, heightCm: Double, sex: BiologicalSex, ageYears: Int, activity: ActivityLevel
    ) -> UserBodyProfile {
        let birthDate = Calendar.current.date(byAdding: .year, value: -ageYears, to: .now) ?? .now
        return UserBodyProfile(
            heightCm: heightCm, weightKg: weightKg, sex: sex, birthDate: birthDate,
            activityLevel: activity
        )
    }
}
