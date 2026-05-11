import Foundation

/// Result of a daily kcal computation, with optional warning for aggressive targets.
public struct KcalTargetResult: Sendable {
    public let dailyKcal: Double
    public let tdee: Double
    public let bmr: Double
    public let bmi: Double
    /// Non-nil when the implied deficit/surplus exceeds 20% of TDEE.
    public let aggressiveGoalWarning: String?
}

/// Pure static functions for fitness math. No state; fully unit-testable.
public enum BodyMath {

    // MARK: - BMI

    public static func bmi(weightKg: Double, heightCm: Double) -> Double {
        guard heightCm > 0 else { return 0 }
        let heightM = heightCm / 100
        return weightKg / (heightM * heightM)
    }

    // MARK: - BMR (Mifflin–St Jeor)

    public static func bmr(profile: UserBodyProfile) -> Double {
        let base = 10 * profile.weightKg + 6.25 * profile.heightCm - 5 * Double(profile.ageYears)
        switch profile.sex {
        case .male:           return base + 5
        case .female:         return base - 161
        case .other:          return base - 78  // average of male/female offsets
        }
    }

    // MARK: - TDEE

    public static func tdee(profile: UserBodyProfile) -> Double {
        bmr(profile: profile) * profile.activityLevel.factor
    }

    // MARK: - Daily kcal target

    public static func dailyKcalTarget(profile: UserBodyProfile) -> KcalTargetResult {
        let bmiValue = bmi(weightKg: profile.weightKg, heightCm: profile.heightCm)
        let bmrValue = bmr(profile: profile)
        let tdeeValue = tdee(profile: profile)

        var adjustment: Double = 0
        var warning: String? = nil

        if let goalKg = profile.goalWeightKg,
           let targetDate = profile.targetDate,
           targetDate > .now {
            let deltaKg = goalKg - profile.weightKg
            let days = max(1, Calendar.current.dateComponents([.day], from: .now, to: targetDate).day ?? 1)
            // 1 kg ≈ 7700 kcal
            let dailyDelta = (deltaKg * 7700) / Double(days)
            let maxAdjustment = tdeeValue * 0.20
            if abs(dailyDelta) > maxAdjustment {
                warning = "Your goal requires a \(Int(abs(dailyDelta))) kcal/day \(deltaKg < 0 ? "deficit" : "surplus"), which exceeds the safe 20% limit. Consider a longer timeline."
                adjustment = dailyDelta < 0 ? -maxAdjustment : maxAdjustment
            } else {
                adjustment = dailyDelta
            }
        }

        return KcalTargetResult(
            dailyKcal: max(1200, tdeeValue + adjustment),
            tdee: tdeeValue,
            bmr: bmrValue,
            bmi: bmiValue,
            aggressiveGoalWarning: warning
        )
    }

    // MARK: - Per-exercise kcal

    /// MET-based calorie burn estimate.
    /// - Parameters:
    ///   - metValue: MET value from the exercise library (1–15 range).
    ///   - durationMin: Duration in minutes.
    ///   - weightKg: User body weight.
    public static func kcalBurned(metValue: Double, durationMin: Int, weightKg: Double) -> Double {
        (metValue * weightKg * 3.5 / 200) * Double(durationMin)
    }
}
