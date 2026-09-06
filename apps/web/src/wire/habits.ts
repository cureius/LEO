import { refDateToJSDate, jsDateToRefDate } from './dates'
import type { Habit, HabitFrequency, HabitForgiveness, RecurrenceRule, TimeOfDay } from '@/domain/types'

// ---------------------------------------------------------------------------
// Raw wire shapes — LEO/Domain/Habits/Habit.swift (hand-written Codable,
// confirmed from source, not auto-synthesized guesswork).
// ---------------------------------------------------------------------------

type WireHabit = {
  id: string
  name: string
  frequency: HabitFrequency
  timeHint?: TimeOfDay
  targetDurationSeconds?: number
  forgiveness: HabitForgiveness
  recurrenceRuleRaw: string
  createdAt: number
  isArchived: boolean
}

/**
 * Decode a `habits` row's `data` text column into a Habit.
 *
 * `RecurrenceRule.extensions` is intentionally always `[]` here: SnapshotHabit
 * (the native encoder) never serializes it, so a habit's extensions are
 * already lost the moment it round-trips through Supabase on iOS/Mac too.
 * Reading it as populated here would make the web client *more* correct
 * than native for the same row, which is worse than matching — see
 * domain/types.ts RecurrenceRule doc comment. Fixing the native encoder is a
 * separate, explicitly out-of-scope ticket.
 */
export function decodeHabitPayload(dataJson: string): Habit | undefined {
  try {
    const w = JSON.parse(dataJson) as WireHabit
    return {
      id: w.id,
      name: w.name,
      frequency: w.frequency,
      timeHint: w.timeHint,
      targetDurationSeconds: w.targetDurationSeconds,
      forgiveness: w.forgiveness,
      recurrenceRuleRaw: w.recurrenceRuleRaw,
      createdAt: refDateToJSDate(w.createdAt),
      isArchived: w.isArchived,
    }
  } catch {
    return undefined
  }
}

export function encodeHabitPayload(habit: Habit): string {
  const w: WireHabit = {
    id: habit.id,
    name: habit.name,
    frequency: habit.frequency,
    timeHint: habit.timeHint,
    targetDurationSeconds: habit.targetDurationSeconds,
    forgiveness: habit.forgiveness,
    recurrenceRuleRaw: habit.recurrenceRuleRaw,
    createdAt: jsDateToRefDate(habit.createdAt),
    isArchived: habit.isArchived,
  }
  return JSON.stringify(w)
}

/** Port of Habit.swift's TimeOfDay.hintHour, used by HabitMaterializer (Phase 3). */
export function timeOfDayHintHour(hint: TimeOfDay): number {
  switch (hint.type) {
    case 'morning':
      return 7
    case 'afternoon':
      return 13
    case 'evening':
      return 19
    case 'specific':
      return hint.hour
  }
}

/** Build a plain RecurrenceRule wire object for a raw RRULE string with no extensions. */
export function recurrenceRule(raw: string, extensions: RecurrenceRule['extensions'] = []): RecurrenceRule {
  return { raw, extensions }
}
