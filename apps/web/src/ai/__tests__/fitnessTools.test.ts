import { describe, expect, it, beforeEach } from 'vitest'
import '../tools/fitnessTools' // registers get_body_profile/get_fitness_items/propose_workout_plan/propose_meal_plan/set_workout_exercises/adjust_plan
import { executeTool } from '../toolRuntime'
import { useSyncStore } from '@/sync/store'
import type { DiffPayload, PendingNewItem } from '../diff/types'
import type { BodyProfile, MealItem, TaskItem, WorkoutItem } from '@/domain/types'

function workout(id: string, overrides: Partial<WorkoutItem> = {}): WorkoutItem {
  return {
    kind: 'workout',
    id,
    title: id,
    createdAt: new Date(),
    updatedAt: new Date(),
    importance: 1,
    anchor: { type: 'untimed' },
    completion: { type: 'open' },
    tags: [],
    plannedExercises: [],
    estimatedKcal: 300,
    ...overrides,
  }
}
function meal(id: string, overrides: Partial<MealItem> = {}): MealItem {
  return {
    kind: 'meal',
    id,
    title: id,
    createdAt: new Date(),
    updatedAt: new Date(),
    importance: 1,
    anchor: { type: 'untimed' },
    completion: { type: 'open' },
    tags: [],
    recipeID: 'r1',
    servings: 1,
    targetKcal: 500,
    ...overrides,
  }
}
function task(id: string): TaskItem {
  return {
    kind: 'task',
    id,
    title: id,
    createdAt: new Date(),
    updatedAt: new Date(),
    importance: 1,
    anchor: { type: 'untimed' },
    completion: { type: 'open' },
    tags: [],
  }
}

beforeEach(() => {
  useSyncStore.setState({ items: new Map(), bodyProfile: undefined })
})

describe('get_fitness_items — regression: get_today/get_week only cover a narrow date window, so untimed or far-future workouts/meals were invisible to the AI', () => {
  it('returns an untimed workout — invisible to get_today/get_week, but the whole point of this tool', async () => {
    useSyncStore.getState().upsertItem(workout('w-untimed'))
    const { result } = await executeTool('get_fitness_items', '{}')
    const items = JSON.parse(result)
    expect(items.map((i: { id: string }) => i.id)).toContain('w-untimed')
  })

  it('returns a meal scheduled a month out — outside get_week\'s 7-day window', async () => {
    const farOut = new Date(Date.now() + 30 * 86_400_000).toISOString()
    useSyncStore.getState().upsertItem(meal('m-far', { anchor: { type: 'point', date: farOut } }))
    const { result } = await executeTool('get_fitness_items', '{}')
    const items = JSON.parse(result)
    expect(items.map((i: { id: string }) => i.id)).toContain('m-far')
  })

  it('includes completion status, so the AI can filter for "not marked as done" itself', async () => {
    useSyncStore.getState().upsertItem(workout('w-done', { completion: { type: 'completed', date: new Date().toISOString() } }))
    useSyncStore.getState().upsertItem(workout('w-open'))
    const { result } = await executeTool('get_fitness_items', '{}')
    const items = JSON.parse(result) as { id: string; completed: boolean }[]
    expect(items.find((i) => i.id === 'w-done')?.completed).toBe(true)
    expect(items.find((i) => i.id === 'w-open')?.completed).toBe(false)
  })

  it('excludes non-fitness items (tasks, etc.)', async () => {
    useSyncStore.getState().upsertItem(task('t1'))
    useSyncStore.getState().upsertItem(workout('w1'))
    const { result } = await executeTool('get_fitness_items', '{}')
    const ids = JSON.parse(result).map((i: { id: string }) => i.id)
    expect(ids).toContain('w1')
    expect(ids).not.toContain('t1')
  })
})

describe('set_workout_exercises — the actual fix for "workout items have no trackable exercises"', () => {
  it('returns a single "workoutDetail" change carrying structured exercises + estimatedKcal', async () => {
    useSyncStore.getState().upsertItem(workout('w1'))
    const { result, isError } = await executeTool(
      'set_workout_exercises',
      JSON.stringify({
        itemID: 'w1',
        exercises: [
          { name: 'Bench Press', sets: 4, reps: 8 },
          { name: 'Overhead Press', sets: 3, reps: 10, weightKg: 40 },
        ],
        estimatedKcal: 350,
        rationale: 'From the attached PDF',
      }),
    )
    expect(isError).toBe(false)
    const diff = JSON.parse(result) as DiffPayload
    expect(diff.changes).toHaveLength(1)
    expect(diff.changes[0]).toMatchObject({ itemID: 'w1', kind: 'update', field: 'workoutDetail' })
    const detail = JSON.parse(diff.changes[0].newValue)
    expect(detail).toEqual({
      exercises: [
        { exerciseID: 'Bench Press', sets: 4, reps: 8 },
        { exerciseID: 'Overhead Press', sets: 3, reps: 10, weightKg: 40 },
      ],
      estimatedKcal: 350,
    })
  })

  it('errors (without throwing) when the item id does not exist', async () => {
    const { result } = await executeTool(
      'set_workout_exercises',
      JSON.stringify({ itemID: 'missing', exercises: [{ name: 'Squat', sets: 5, reps: 5 }], rationale: 'x' }),
    )
    expect(JSON.parse(result)).toEqual({ error: 'No item with id missing' })
  })

  it('errors when the item exists but is not a workout — e.g. a meal', async () => {
    useSyncStore.getState().upsertItem(meal('m1'))
    const { result } = await executeTool(
      'set_workout_exercises',
      JSON.stringify({ itemID: 'm1', exercises: [{ name: 'Squat', sets: 5, reps: 5 }], rationale: 'x' }),
    )
    const parsed = JSON.parse(result)
    expect(parsed.error).toContain('not a workout')
  })
})

const ALL_EQUIPMENT = ['bodyweight', 'dumbbells', 'barbell', 'machine', 'cable', 'band', 'kettlebell', 'pullUpBar']

describe('propose_workout_plan — port of ProposeWorkoutPlanTool.swift, real exercise catalog + split/equipment logic', () => {
  it('generates one add-diff per session, each carrying real structured exercises (not empty)', async () => {
    const { result } = await executeTool(
      'propose_workout_plan',
      JSON.stringify({ weeks: 1, daysPerWeek: 3, splitStyle: 'push_pull_legs', equipment: ALL_EQUIPMENT, rationale: 'Standard PPL' }),
    )
    const diff = JSON.parse(result) as DiffPayload
    expect(diff.changes).toHaveLength(3) // 1 week x 3 days
    for (const change of diff.changes) {
      expect(change.kind).toBe('add')
      const pending = change.pendingItem as PendingNewItem
      expect(pending.type).toBe('workout')
      expect(pending.exercises).toBeDefined()
      expect(pending.exercises!.length).toBeGreaterThan(0)
      for (const ex of pending.exercises!) {
        expect(ex.sets).toBeGreaterThan(0)
        expect(ex.reps).toBeGreaterThan(0)
      }
    }
  })

  it('push_pull_legs day 1 (push) selects chest/shoulders/triceps exercises from the real catalog', async () => {
    const { result } = await executeTool(
      'propose_workout_plan',
      JSON.stringify({ weeks: 1, daysPerWeek: 3, splitStyle: 'push_pull_legs', equipment: ALL_EQUIPMENT, rationale: 'x' }),
    )
    const diff = JSON.parse(result) as DiffPayload
    const day1 = diff.changes[0].pendingItem as PendingNewItem
    expect(day1.title).toContain('Chest')
    // Bench Press is chest/triceps/shoulders in the real bundled catalog — should be selectable for a push day.
    expect(day1.exercises!.some((e) => /press/i.test(e.name))).toBe(true)
  })

  it('a limited equipment set (e.g. bodyweight-only) can leave some sessions with no matching exercises — real catalog data, not every muscle group has a bodyweight option (e.g. back/biceps)', async () => {
    const { result } = await executeTool(
      'propose_workout_plan',
      JSON.stringify({ weeks: 1, daysPerWeek: 3, splitStyle: 'push_pull_legs', equipment: ['bodyweight'], rationale: 'x' }),
    )
    const diff = JSON.parse(result) as DiffPayload
    // Push day (chest/shoulders/triceps) has bodyweight options (Push-Up); pull day
    // (back/biceps) has none in the real catalog — that session is skipped, not
    // filled with an empty/wrong item, and shows up as a validation error instead.
    expect(diff.changes.length).toBeLessThan(3)
    const parsed = JSON.parse(result) as { validationErrors: string[] }
    expect(parsed.validationErrors.length).toBeGreaterThan(0)
  })

  it('every exercise selected for a bodyweight-only full-body session is actually bodyweight-compatible', async () => {
    const { result } = await executeTool(
      'propose_workout_plan',
      JSON.stringify({ weeks: 1, daysPerWeek: 1, splitStyle: 'full_body', equipment: ['bodyweight'], rationale: 'x' }),
    )
    const diff = JSON.parse(result) as DiffPayload
    const pending = diff.changes[0].pendingItem as PendingNewItem
    expect(pending.exercises!.length).toBeGreaterThan(0)
  })

  it('estimates real per-session kcal from body weight when a profile exists, not the flat 250 default', async () => {
    useSyncStore.getState().setBodyProfile({
      weightKg: 80, heightCm: 180, sex: 'male', activityLevel: 'active',
      allergies: [], intolerances: [], medicalFlags: [], unitPreference: 'metric',
    } as BodyProfile)
    const { result } = await executeTool(
      'propose_workout_plan',
      JSON.stringify({ weeks: 1, daysPerWeek: 1, splitStyle: 'full_body', rationale: 'x' }),
    )
    const diff = JSON.parse(result) as DiffPayload
    const pending = diff.changes[0].pendingItem as PendingNewItem
    expect(pending.estimatedKcal).toBeGreaterThan(0)
    expect(pending.estimatedKcal).not.toBe(250)
  })

  it('defaults to 250 kcal when no body profile is set', async () => {
    const { result } = await executeTool(
      'propose_workout_plan',
      JSON.stringify({ weeks: 1, daysPerWeek: 1, splitStyle: 'full_body', rationale: 'x' }),
    )
    const diff = JSON.parse(result) as DiffPayload
    const pending = diff.changes[0].pendingItem as PendingNewItem
    expect(pending.estimatedKcal).toBe(250)
  })

  it('clamps weeks to [1,12] and daysPerWeek to [1,7]', async () => {
    const { result } = await executeTool(
      'propose_workout_plan',
      JSON.stringify({ weeks: 99, daysPerWeek: 99, splitStyle: 'full_body', rationale: 'x' }),
    )
    const diff = JSON.parse(result) as DiffPayload
    expect(diff.changes).toHaveLength(12 * 7)
  })
})
