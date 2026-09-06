import { describe, expect, it } from 'vitest'
import { bmi, bmr, kcalBurned, tdee } from '../bodyMath'
import type { BodyProfile } from '@/domain/types'

function profile(overrides: Partial<BodyProfile> = {}): BodyProfile {
  return {
    weightKg: 74,
    heightCm: 180,
    sex: 'male',
    birthDate: new Date(2000, 8, 9), // ~25-26 years old depending on "now"
    activityLevel: 'active',
    allergies: [],
    intolerances: [],
    medicalFlags: [],
    unitPreference: 'metric',
    ...overrides,
  }
}

describe('bmi', () => {
  it('computes weight over height-in-meters squared', () => {
    expect(bmi(74, 180)).toBeCloseTo(74 / 1.8 ** 2, 2)
  })
})

describe('bmr — Mifflin-St Jeor, confirmed formula from BodyMath.swift', () => {
  it('matches the confirmed formula for a male profile: 10*w + 6.25*h - 5*age + 5', () => {
    const now = new Date(2026, 6, 18)
    const p = profile({ birthDate: new Date(2000, 8, 9) }) // born before `now`'s month/day -> age 25
    const age = 2026 - 2000 - 1 // birthday (Sep 9) hasn't happened yet by July 18
    const expected = 10 * 74 + 6.25 * 180 - 5 * age + 5
    expect(bmr(p)).toBeCloseTo(expected, 5)
    void now
  })

  it('applies -161 for female instead of +5', () => {
    const male = bmr(profile({ sex: 'male' }))!
    const female = bmr(profile({ sex: 'female' }))!
    expect(female).toBeCloseTo(male - 166, 5) // -161 vs +5 is a 166 gap
  })

  it('applies -78 for other (average of the male/female offsets)', () => {
    const other = bmr(profile({ sex: 'other' }))!
    const male = bmr(profile({ sex: 'male' }))!
    expect(other).toBeCloseTo(male - 83, 5) // +5 - (-78) = 83
  })

  it('returns undefined when required fields are missing', () => {
    expect(bmr(profile({ weightKg: undefined }))).toBeUndefined()
    expect(bmr(profile({ birthDate: undefined }))).toBeUndefined()
  })
})

describe('tdee', () => {
  it('multiplies BMR by the activity factor', () => {
    const p = profile({ activityLevel: 'sedentary' })
    expect(tdee(p)).toBeCloseTo(bmr(p)! * 1.2, 5)
  })

  it('a more active level yields a higher TDEE for the same BMR', () => {
    const sedentary = tdee(profile({ activityLevel: 'sedentary' }))!
    const veryActive = tdee(profile({ activityLevel: 'veryActive' }))!
    expect(veryActive).toBeGreaterThan(sedentary)
  })

  it('returns undefined without an activity level', () => {
    expect(tdee(profile({ activityLevel: undefined }))).toBeUndefined()
  })
})

describe('kcalBurned — port of BodyMath.swift, standard MET formula', () => {
  it('MET 8, 30 min, 80kg → expected range', () => {
    // (8 * 80 * 3.5 / 200) * 30 = 336
    expect(kcalBurned(8, 30, 80)).toBeCloseTo(336, 5)
  })

  it('scales proportionally with duration', () => {
    const thirty = kcalBurned(6, 30, 70)
    const sixty = kcalBurned(6, 60, 70)
    expect(sixty).toBeCloseTo(thirty * 2, 5)
  })
})
