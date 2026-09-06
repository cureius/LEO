import { refDateToJSDate, jsDateToRefDate } from './dates'
import type { ActivityLevel, BodyProfile, Measurement, Sex, UnitPreference } from '@/domain/types'

// ---------------------------------------------------------------------------
// body_profiles.data / measurements.data — confirmed against a real live row
// this session, NOT the SnapshotDTO base64/tags pattern items/habits use.
// ---------------------------------------------------------------------------

type WireBodyProfile = {
  heightCm?: number
  weightKg?: number
  sex?: Sex
  birthDate?: number
  bodyFatPct?: number
  activityLevel?: ActivityLevel
  goalWeightKg?: number
  goalPhysique?: string
  targetDate?: number
  dietType?: string
  allergies: string[]
  intolerances: string[]
  medicalFlags: string[]
  unitPreference: UnitPreference
}

export function decodeBodyProfilePayload(dataJson: string): BodyProfile | undefined {
  try {
    const w = JSON.parse(dataJson) as WireBodyProfile
    return {
      heightCm: w.heightCm,
      weightKg: w.weightKg,
      sex: w.sex,
      birthDate: w.birthDate !== undefined ? refDateToJSDate(w.birthDate) : undefined,
      bodyFatPct: w.bodyFatPct,
      activityLevel: w.activityLevel,
      goalWeightKg: w.goalWeightKg,
      goalPhysique: w.goalPhysique,
      targetDate: w.targetDate !== undefined ? refDateToJSDate(w.targetDate) : undefined,
      dietType: w.dietType,
      allergies: w.allergies ?? [],
      intolerances: w.intolerances ?? [],
      medicalFlags: w.medicalFlags ?? [],
      unitPreference: w.unitPreference,
    }
  } catch {
    return undefined
  }
}

export function encodeBodyProfilePayload(profile: BodyProfile): string {
  const w: WireBodyProfile = {
    heightCm: profile.heightCm,
    weightKg: profile.weightKg,
    sex: profile.sex,
    birthDate: profile.birthDate ? jsDateToRefDate(profile.birthDate) : undefined,
    bodyFatPct: profile.bodyFatPct,
    activityLevel: profile.activityLevel,
    goalWeightKg: profile.goalWeightKg,
    goalPhysique: profile.goalPhysique,
    targetDate: profile.targetDate ? jsDateToRefDate(profile.targetDate) : undefined,
    dietType: profile.dietType,
    allergies: profile.allergies,
    intolerances: profile.intolerances,
    medicalFlags: profile.medicalFlags,
    unitPreference: profile.unitPreference,
  }
  return JSON.stringify(w)
}

type WireMeasurement = {
  id: string
  weightKg?: number
  bodyFatPct?: number
  source: string
  date: number
}

export function decodeMeasurementPayload(dataJson: string): Measurement | undefined {
  try {
    const w = JSON.parse(dataJson) as WireMeasurement
    return {
      id: w.id,
      weightKg: w.weightKg,
      bodyFatPct: w.bodyFatPct,
      source: w.source,
      date: refDateToJSDate(w.date),
    }
  } catch {
    return undefined
  }
}

export function encodeMeasurementPayload(measurement: Measurement): string {
  const w: WireMeasurement = {
    id: measurement.id,
    weightKg: measurement.weightKg,
    bodyFatPct: measurement.bodyFatPct,
    source: measurement.source,
    date: jsDateToRefDate(measurement.date),
  }
  return JSON.stringify(w)
}
