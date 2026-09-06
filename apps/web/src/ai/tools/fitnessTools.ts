import { registerTool } from '../toolRuntime'
import { bmi, bmr, kcalBurned, tdee } from '../bodyMath'
import { EXERCISE_CATALOG, RECIPE_CATALOG, type Equipment, type Exercise, type MuscleGroup } from './fitnessCatalog'
import { selectItemsArray, useSyncStore } from '@/sync/store'
import { anchorSortDate } from '@/wire/anchor'
import type { DiffChange, DiffPayload, PendingNewItem } from '../diff/types'
import type { PlannedExercise } from '@/domain/types'

/**
 * Port of the 4 Swift fitness tools (GetBodyProfileTool, ProposeWorkoutPlanTool,
 * ProposeMealPlanTool, AdjustPlanTool) into the same registry as the other
 * tools — not a separate subsystem, confirmed against ToolRuntime.swift's
 * conditional registration (`if let bodyProfileRepo = ...`). `get_fitness_items`
 * (below) is a 5th, web-only addition — not a port — closing a real gap: the
 * generic read tools (get_today/get_week) only surface items with a date
 * inside a narrow window, so an untimed or out-of-range workout/meal was
 * completely invisible to the AI. Caught live: asked to "remove all workout
 * and meal items not marked as done," the AI reported none existed, because
 * it structurally had no tool that could see them — not because there were
 * none.
 */

registerTool(
  {
    name: 'get_body_profile',
    description: "Get the user's body profile, recent measurements, and computed BMI/BMR/TDEE.",
    input_schema: { type: 'object', properties: {} },
  },
  async () => {
    const store = useSyncStore.getState()
    const profile = store.bodyProfile
    if (!profile) return { error: 'No body profile set up yet' }
    return {
      profile,
      bmi: profile.weightKg && profile.heightCm ? Math.round(bmi(profile.weightKg, profile.heightCm) * 10) / 10 : null,
      bmr: bmr(profile) ? Math.round(bmr(profile)!) : null,
      tdee: tdee(profile) ? Math.round(tdee(profile)!) : null,
    }
  },
)

registerTool(
  {
    name: 'get_fitness_items',
    description:
      "Get EVERY workout and meal item, regardless of date or completion status — including untimed ones and ones outside the next 7 days. get_today/get_week only cover a narrow scheduled window, so use this instead whenever asked about workout/meal plans broadly (e.g. 'remove all my unfinished workouts', 'what meals do I have planned'), not just this week's.",
    input_schema: { type: 'object', properties: {} },
  },
  async () => {
    const items = selectItemsArray(useSyncStore.getState())
    return items
      .filter((i) => i.kind === 'workout' || i.kind === 'meal')
      .map((i) => ({
        id: i.id,
        kind: i.kind,
        title: i.title,
        completed: i.completion.type !== 'open',
        when: anchorSortDate(i.anchor)?.toISOString() ?? null,
      }))
  },
)

type SplitStyle = 'full_body' | 'upper_lower' | 'push_pull_legs' | 'freeform'
const SPLIT_DISPLAY_NAMES: Record<SplitStyle, string> = {
  full_body: 'Full body',
  upper_lower: 'Upper / Lower',
  push_pull_legs: 'Push / Pull / Legs',
  freeform: 'Freeform',
}
const EQUIPMENT_VALUES = ['bodyweight', 'dumbbells', 'barbell', 'machine', 'cable', 'band', 'kettlebell', 'pullUpBar'] as const

/** Port of ProposeWorkoutPlanTool.swift's splitGroups(for:daysPerWeek:). */
function splitGroups(split: SplitStyle, daysPerWeek: number): MuscleGroup[][] {
  switch (split) {
    case 'full_body':
      return Array.from({ length: daysPerWeek }, () => ['chest', 'back', 'quads', 'core'])
    case 'upper_lower':
      return daysPerWeek >= 4
        ? [['chest', 'back', 'shoulders'], ['quads', 'hamstrings', 'glutes'], ['chest', 'back', 'shoulders'], ['quads', 'hamstrings', 'glutes']]
        : [['chest', 'back', 'shoulders'], ['quads', 'hamstrings', 'glutes']]
    case 'push_pull_legs':
      return [['chest', 'shoulders', 'triceps'], ['back', 'biceps'], ['quads', 'hamstrings', 'glutes', 'calves']]
    case 'freeform':
      return Array.from({ length: daysPerWeek }, () => ['fullBody'])
  }
}

/** Port of ProposeWorkoutPlanTool.swift's dayOffset(for:daysPerWeek:) — spreads sessions across the week. */
function dayOffset(dayIdx: number, daysPerWeek: number): number {
  const stride = Math.floor(7 / Math.max(1, daysPerWeek))
  return dayIdx * stride
}

/** Port of ProposeWorkoutPlanTool.swift's pickExercises — filters by muscle group, ranks by MET (intensity). */
function pickExercises(muscleGroups: MuscleGroup[], exercises: Exercise[], count: number): Exercise[] {
  const target = new Set(muscleGroups)
  const filtered = exercises.filter((ex) => ex.muscleGroups.some((g) => target.has(g)))
  return [...filtered].sort((a, b) => b.metValue - a.metValue).slice(0, count)
}

function sessionTitle(muscleGroups: MuscleGroup[], week: number, day: number): string {
  const groups = muscleGroups.map((g) => g.charAt(0).toUpperCase() + g.slice(1)).join(' + ')
  return `W${week}D${day} ${groups}`
}

/** Direct port of ProposeWorkoutPlanTool.swift's nextMonday(): this week's Monday if
 *  still upcoming, otherwise next week's — in practice always next week's, since
 *  "this week's Monday at midnight" is never later than "now" within the same week. */
function nextMonday(from: Date = new Date()): Date {
  const day = from.getDay() // 0=Sun..6=Sat
  const diffFromMonday = (day + 6) % 7
  const monday = new Date(from.getFullYear(), from.getMonth(), from.getDate() - diffFromMonday)
  if (monday.getTime() > from.getTime()) return monday
  return new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + 7)
}

function isEquipment(value: string): value is Equipment {
  return (EQUIPMENT_VALUES as readonly string[]).includes(value)
}

registerTool(
  {
    name: 'propose_workout_plan',
    description: 'Generate a multi-week workout plan as a Diff for user review, selecting real exercises from the bundled library by muscle group/equipment/intensity. Call get_body_profile first.',
    input_schema: {
      type: 'object',
      properties: {
        weeks: { type: 'integer', description: 'Defaults to 4' },
        daysPerWeek: { type: 'integer', description: 'Defaults to 3' },
        equipment: { type: 'array', items: { type: 'string' }, description: 'Available equipment. Values: bodyweight, dumbbells, barbell, machine, cable, band, kettlebell, pullUpBar' },
        splitStyle: { type: 'string', enum: ['full_body', 'upper_lower', 'push_pull_legs', 'freeform'] },
        notes: { type: 'string', description: 'Extra instructions (injuries, preferences)' },
        startDate: { type: 'string', description: 'ISO8601 date for plan start. Defaults to next Monday.' },
        rationale: { type: 'string' },
      },
      required: ['rationale'],
    },
  },
  async (input) => {
    const raw = input as {
      weeks?: number; daysPerWeek?: number; equipment?: string[]; splitStyle?: string
      notes?: string; startDate?: string; rationale: string
    }
    const weeks = Math.max(1, Math.min(12, raw.weeks ?? 4))
    const daysPerWeek = Math.max(1, Math.min(7, raw.daysPerWeek ?? 3))
    const split: SplitStyle = (['full_body', 'upper_lower', 'push_pull_legs', 'freeform'] as const).includes(raw.splitStyle as SplitStyle)
      ? (raw.splitStyle as SplitStyle)
      : 'full_body'

    const equipmentFilter = new Set<Equipment>(
      raw.equipment && raw.equipment.length > 0 ? raw.equipment.filter(isEquipment) : ['bodyweight'],
    )
    const availableExercises = EXERCISE_CATALOG.filter((ex) => ex.equipment.some((e) => equipmentFilter.has(e)))

    const startDate = raw.startDate ? new Date(raw.startDate) : nextMonday()
    const profile = useSyncStore.getState().bodyProfile

    const changes: DiffChange[] = []
    const validationErrors: string[] = []
    const sessionGroups = splitGroups(split, daysPerWeek)

    for (let week = 0; week < weeks; week++) {
      const weekOffset = week * 7
      sessionGroups.forEach((muscleGroups, dayIdx) => {
        const sessionDate = new Date(startDate)
        sessionDate.setDate(sessionDate.getDate() + weekOffset + dayOffset(dayIdx, daysPerWeek))

        const exercises = pickExercises(muscleGroups, availableExercises, 4)
        if (exercises.length === 0) {
          validationErrors.push(`No exercises found for ${muscleGroups.join('+')} with given equipment.`)
          return
        }

        let estimatedKcal: number
        if (profile?.weightKg) {
          const totalMins = exercises.reduce((n, ex) => n + ex.defaultSets * 2 + (ex.defaultDurationMin ?? 3), 0)
          const avgMet = exercises.reduce((n, ex) => n + ex.metValue, 0) / exercises.length
          estimatedKcal = Math.round(kcalBurned(avgMet, totalMins, profile.weightKg))
        } else {
          estimatedKcal = 250
        }

        const title = sessionTitle(muscleGroups, week + 1, dayIdx + 1)
        const sessionStart = new Date(sessionDate)
        sessionStart.setHours(7, 0, 0, 0)

        const pendingItem: PendingNewItem = {
          title,
          type: 'workout',
          start: sessionStart.toISOString(),
          notes: `Week ${week + 1}, Day ${dayIdx + 1}. Exercises: ${exercises.map((e) => e.name).join(', ')}`,
          exercises: exercises.map((ex) => ({ name: ex.name, sets: ex.defaultSets, reps: ex.defaultReps })),
          estimatedKcal,
        }
        changes.push({ itemID: crypto.randomUUID(), kind: 'add', field: 'title', newValue: title, pendingItem })
      })
    }

    const kcalTarget = profile ? tdee(profile) : undefined
    const kcalNote = kcalTarget ? ` Daily kcal target: ${Math.round(kcalTarget)} kcal.` : ''
    const equipmentNote = [...equipmentFilter].join(', ')
    const rationale = `${weeks}-week ${SPLIT_DISPLAY_NAMES[split]} plan, ${daysPerWeek} days/week.${kcalNote} Equipment: ${equipmentNote}. ${raw.notes ?? ''}`.trim()

    return { changes, rationale, validationErrors }
  },
)

registerTool(
  {
    name: 'propose_meal_plan',
    description: "Propose a meal plan (new meal items) based on the user's body profile and target calories. Returns a Diff for user review.",
    input_schema: {
      type: 'object',
      properties: {
        mealsPerDay: { type: 'number' },
        startDate: { type: 'string', description: 'ISO8601 date to start the plan' },
        rationale: { type: 'string' },
      },
      required: ['mealsPerDay', 'startDate', 'rationale'],
    },
  },
  async (input) => {
    const { mealsPerDay, startDate, rationale } = input as { mealsPerDay: number; startDate: string; rationale: string }
    const start = new Date(startDate)
    const changes: DiffChange[] = []
    for (let i = 0; i < Math.min(mealsPerDay, RECIPE_CATALOG.length); i++) {
      const recipe = RECIPE_CATALOG[i]
      const date = new Date(start.getTime())
      date.setHours(8 + i * 4, 0, 0, 0)
      changes.push({
        itemID: crypto.randomUUID(),
        kind: 'add',
        field: 'title',
        newValue: recipe.name,
        pendingItem: { title: `${recipe.name} (~${recipe.kcal} kcal)`, type: 'meal', start: date.toISOString() },
      })
    }
    return { changes, rationale } satisfies DiffPayload
  },
)

/**
 * 6th web-only addition (see get_fitness_items above) — not a port. Real gap
 * found live: adjust_plan (below) can only ever write a free-text `notes`
 * field, so an instruction like "Day 1 is Bench, Incline DB press, OHP..."
 * landed as a text blob instead of individually trackable exercise rows —
 * WorkoutRow.tsx already renders `plannedExercises` as sets/reps pills when
 * populated, but nothing in the tool registry could ever populate it. This
 * closes that gap directly rather than teaching adjust_plan to string-match
 * exercise syntax out of free text, which would be far more fragile than
 * just giving the model a structured tool for the structured field.
 */
registerTool(
  {
    name: 'set_workout_exercises',
    description:
      "Set the exact exercises (name, sets, reps, optional weight) on an existing workout item, so they show up as individually trackable rows in the Fitness tab — not just a text note. Use this whenever the user gives (or you're deriving from an attached plan/PDF) specific exercises with sets/reps for a workout; use adjust_plan instead only for non-exercise changes (rescheduling, cancelling, freeform notes). Returns a Diff for user review.",
    input_schema: {
      type: 'object',
      properties: {
        itemID: { type: 'string', description: 'The workout item to update — get this from get_fitness_items/get_today/get_week.' },
        exercises: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              name: { type: 'string', description: 'e.g. "Bench Press", "Incline DB Press"' },
              sets: { type: 'number' },
              reps: { type: 'number' },
              weightKg: { type: 'number', description: 'Optional target/last-used weight in kg' },
            },
            required: ['name', 'sets', 'reps'],
          },
        },
        estimatedKcal: { type: 'number', description: 'Optional estimated calories burned for the whole session' },
        rationale: { type: 'string' },
      },
      required: ['itemID', 'exercises', 'rationale'],
    },
  },
  async (input) => {
    const { itemID, exercises, estimatedKcal, rationale } = input as {
      itemID: string
      exercises: { name: string; sets: number; reps: number; weightKg?: number }[]
      estimatedKcal?: number
      rationale: string
    }
    const item = useSyncStore.getState().getItem(itemID)
    if (!item) return { error: `No item with id ${itemID}` }
    if (item.kind !== 'workout') return { error: `Item ${itemID} is a "${item.kind}", not a workout — set_workout_exercises only applies to workout items` }

    const plannedExercises: PlannedExercise[] = exercises.map((e) => ({
      exerciseID: e.name,
      sets: e.sets,
      reps: e.reps,
      ...(e.weightKg !== undefined ? { weightKg: e.weightKg } : {}),
    }))

    // A single change, not two (plannedExercises + estimatedKcal) — DiffReview
    // keys/dedupes changes by itemID, so two changes on the same item would
    // silently collide (same React key, shared accept/reject checkbox).
    const change: DiffChange = {
      itemID,
      kind: 'update',
      field: 'workoutDetail',
      newValue: JSON.stringify({ exercises: plannedExercises, estimatedKcal }),
    }
    return { changes: [change], rationale } satisfies DiffPayload
  },
)

/**
 * Deliberately this naive — port of AdjustPlanTool.swift, which does crude
 * string-matching on the instruction rather than real field mutation, and
 * appends a note rather than editing structured fields. Not worth improving
 * beyond parity in this phase; ported as-is. For exercise/sets/reps changes
 * specifically, use set_workout_exercises above instead — that's the actual
 * fix for the gap this tool's naivety used to paper over with a notes dump.
 */
registerTool(
  {
    name: 'adjust_plan',
    description: "Adjust an existing workout or meal item based on a free-text instruction (e.g. 'remove this', 'swap for something lighter').",
    input_schema: {
      type: 'object',
      properties: { itemID: { type: 'string' }, instruction: { type: 'string' }, rationale: { type: 'string' } },
      required: ['itemID', 'instruction', 'rationale'],
    },
  },
  async (input) => {
    const { itemID, instruction, rationale } = input as { itemID: string; instruction: string; rationale: string }
    const store = useSyncStore.getState()
    const title = store.getItem(itemID)?.title ?? 'Unknown item'
    const lower = instruction.toLowerCase()

    let change: DiffChange
    if (['remove', 'delete', 'cancel', 'skip'].some((kw) => lower.includes(kw))) {
      change = { itemID, kind: 'delete', field: 'title', newValue: title }
    } else if (['swap', 'replace'].some((kw) => lower.includes(kw))) {
      change = { itemID, kind: 'update', field: 'notes', newValue: instruction }
    } else {
      change = { itemID, kind: 'update', field: 'notes', newValue: instruction }
    }
    return { changes: [change], rationale } satisfies DiffPayload
  },
)
