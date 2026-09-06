import type { ActivityLevel, BodyProfile, Sex } from '@/domain/types'

/**
 * Port of LEO/Domain/Fitness/BodyMath.swift's BMR formula, confirmed from
 * source this session: Mifflin–St Jeor, `10*weightKg + 6.25*heightCm -
 * 5*age`, +5 male / -161 female / -78 other (average of the two offsets).
 *
 * Activity-level multipliers were NOT re-verified against the exact Swift
 * `ActivityLevel.factor` values (not read this session) — these are the
 * standard, widely-published Mifflin-St Jeor activity multipliers rather
 * than a guess at Swift-specific constants.
 */
const ACTIVITY_FACTORS: Record<ActivityLevel, number> = {
  sedentary: 1.2,
  light: 1.375,
  moderate: 1.55,
  active: 1.725,
  veryActive: 1.9,
}

function ageYears(birthDate: Date, now: Date = new Date()): number {
  let age = now.getFullYear() - birthDate.getFullYear()
  const monthDiff = now.getMonth() - birthDate.getMonth()
  if (monthDiff < 0 || (monthDiff === 0 && now.getDate() < birthDate.getDate())) age--
  return age
}

function sexOffset(sex: Sex | undefined): number {
  if (sex === 'male') return 5
  if (sex === 'female') return -161
  return -78
}

export function bmi(weightKg: number, heightCm: number): number {
  const heightM = heightCm / 100
  return weightKg / (heightM * heightM)
}

export function bmr(profile: BodyProfile): number | undefined {
  if (profile.weightKg === undefined || profile.heightCm === undefined || !profile.birthDate) return undefined
  const base = 10 * profile.weightKg + 6.25 * profile.heightCm - 5 * ageYears(profile.birthDate)
  return base + sexOffset(profile.sex)
}

export function tdee(profile: BodyProfile): number | undefined {
  const base = bmr(profile)
  if (base === undefined || !profile.activityLevel) return undefined
  return base * ACTIVITY_FACTORS[profile.activityLevel]
}

/** Port of BodyMath.swift's kcalBurned — standard MET formula: kcal/min = MET × weightKg × 3.5 / 200. */
export function kcalBurned(metValue: number, durationMin: number, weightKg: number): number {
  return ((metValue * weightKg * 3.5) / 200) * durationMin
}
