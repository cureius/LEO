import type { Anchor, Completion } from '@/wire/anchor'

/** Codable enum raw values — LEO/Domain/Items/Tag.swift:16-18. */
export type TagColor = 'red' | 'orange' | 'yellow' | 'green' | 'teal' | 'blue' | 'indigo' | 'purple' | 'pink' | 'gray'

export type Tag = { id: string; name: string; colorRaw: TagColor }

/** LEO/Domain/Items/EventItem.swift:139-150. */
export type ExternalRef = { source: 'eventKit'; identifier: string; lastSeen: Date }

/** LEO/Domain/Items/AlarmItem.swift:49-56. */
export type AlarmSound = 'alarm_default' | 'alarm_gentle' | 'alarm_urgent' | 'alarm_bell' | 'alarm_chime' | 'haptic_only'

/** LEO/Domain/Items/WorkoutItem.swift:3-23. */
export type PlannedExercise = {
  exerciseID: string
  sets: number
  reps: number
  weightKg?: number
  durationMin?: number
}

/** LEO/Domain/Items/WorkoutItem.swift:25-40 — "Completed" mirror of PlannedExercise. */
export type LoggedExercise = {
  exerciseID: string
  setsCompleted: number
  repsCompleted: number
  weightKg?: number
  durationMin?: number
}

/** LEO/Domain/Fitness/Recipe.swift:3-12. */
export type Macros = { proteinG: number; carbG: number; fatG: number }

type ItemBase = {
  id: string
  title: string
  notes?: string
  createdAt: Date
  updatedAt: Date
  /** Importance.rawValue — 0 low … 3 urgent. */
  importance: number
  anchor: Anchor
  completion: Completion
}

export type TaskItem = ItemBase & {
  kind: 'task'
  tags: Tag[]
  deadline?: Date
  estimatedDurationSeconds?: number
  rruleRaw?: string
}

export type EventItem = ItemBase & {
  kind: 'event'
  tags: Tag[]
  location?: string
  attendees: string[]
  externalRef?: ExternalRef
  rruleRaw?: string
}

export type ReminderItem = ItemBase & {
  kind: 'reminder'
  tags: Tag[]
  leadTime?: number
  externalRef?: ExternalRef
  rruleRaw?: string
}

export type AlarmItem = ItemBase & {
  kind: 'alarm'
  tags: Tag[]
  soundProfileRaw: AlarmSound
  escalates: boolean
  rruleRaw?: string
}

/** No `tags` field on this kind — confirmed absent in SnapshotHabitInstance. */
export type HabitInstanceItem = ItemBase & {
  kind: 'habitInstance'
  habitID: string
  targetDurationSeconds?: number
}

export type WorkoutItem = ItemBase & {
  kind: 'workout'
  tags: Tag[]
  plannedExercises: PlannedExercise[]
  estimatedKcal: number
  actualKcal?: number
  actualExercises?: LoggedExercise[]
  healthKitWorkoutID?: string
}

export type MealItem = ItemBase & {
  kind: 'meal'
  tags: Tag[]
  recipeID: string
  servings: number
  targetKcal: number
  actualKcal?: number
  loggedMacros?: Macros
  healthKitCorrelationID?: string
}

export type DomainItem =
  | TaskItem
  | EventItem
  | ReminderItem
  | AlarmItem
  | HabitInstanceItem
  | WorkoutItem
  | MealItem

export type ItemKind = DomainItem['kind']

/** True for an event/reminder mirrored from the native EventKit — must never
 *  be written by the web client. See wire/items.ts isExternallyManaged(). */
export function isExternallyManagedItem(item: DomainItem): boolean {
  if (item.kind !== 'event' && item.kind !== 'reminder') return false
  return item.externalRef?.source === 'eventKit'
}

// ---------------------------------------------------------------------------
// Habits — LEO/Domain/Habits/Habit.swift
// ---------------------------------------------------------------------------

export type Weekday = 'MO' | 'TU' | 'WE' | 'TH' | 'FR' | 'SA' | 'SU'

/** LEORuleExtension raw values — LEO/Domain/Recurrence/RecurrenceRule.swift:31-35. */
export type LEORuleExtension = 'workdaysOnly' | 'skipUSHolidays' | 'firstWeekdayOfMonth'

/**
 * LEO/Domain/Recurrence/RecurrenceRule.swift:6-16. NOTE: `SnapshotHabit`
 * never serializes `extensions` (confirmed absent in SnapshotDTO.swift) —
 * they are already silently dropped on sync in the native app today. The
 * web wire decoder matches that for parity rather than diverging; see
 * wire/habits.ts.
 */
export type RecurrenceRule = { raw: string; extensions: LEORuleExtension[] }

export type HabitFrequency =
  | { type: 'daily' }
  | { type: 'timesPerWeek'; count: number }
  | { type: 'specificDays'; days: Weekday[] }
  | { type: 'custom'; rule: RecurrenceRule }

export type HabitForgiveness =
  | { type: 'none' }
  | { type: 'misses'; count: number }
  | { type: 'percent'; value: number }

export type TimeOfDay =
  | { type: 'morning' }
  | { type: 'afternoon' }
  | { type: 'evening' }
  | { type: 'specific'; hour: number; minute: number }

export type Habit = {
  id: string
  name: string
  frequency: HabitFrequency
  timeHint?: TimeOfDay
  targetDurationSeconds?: number
  forgiveness: HabitForgiveness
  recurrenceRuleRaw: string
  createdAt: Date
  isArchived: boolean
}

// ---------------------------------------------------------------------------
// Fitness — body_profiles / measurements. Confirmed against a real live row
// (not the SnapshotDTO pattern the item/habit tables use — this is
// `UserBodyProfile` encoded directly, no id/updatedAt inside the payload
// itself; those live on the outer `body_profiles` row (user_id, updated_at)).
// ---------------------------------------------------------------------------

export type Sex = 'male' | 'female' | 'other'
export type ActivityLevel = 'sedentary' | 'light' | 'moderate' | 'active' | 'veryActive'
export type UnitPreference = 'metric' | 'imperial'

export type BodyProfile = {
  heightCm?: number
  weightKg?: number
  sex?: Sex
  birthDate?: Date
  bodyFatPct?: number
  activityLevel?: ActivityLevel
  goalWeightKg?: number
  goalPhysique?: string
  targetDate?: Date
  dietType?: string
  allergies: string[]
  intolerances: string[]
  medicalFlags: string[]
  unitPreference: UnitPreference
}

export type Measurement = {
  id: string
  weightKg?: number
  bodyFatPct?: number
  source: string
  date: Date
}
