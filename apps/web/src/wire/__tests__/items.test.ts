import { describe, expect, it } from 'vitest'
import { decodeItemRow, encodeItemPayload, isExternallyManaged } from '../items'
import type { AlarmItem, EventItem, HabitInstanceItem, MealItem, ReminderItem, TaskItem, WorkoutItem } from '@/domain/types'

import fixtureTask from './fixtures/fixture_task.json'
import fixtureEvent from './fixtures/fixture_event.json'
import fixtureWorkout from './fixtures/fixture_workout.json'
import fixtureMeal from './fixtures/fixture_meal.json'

describe('decodeItemRow against real captured production rows', () => {
  it('decodes a real task row', () => {
    const item = decodeItemRow('task', JSON.stringify(fixtureTask))
    expect(item?.kind).toBe('task')
    expect(item?.id).toBe('A2572F37-0475-4DA4-A67F-DC9F027EE038')
    expect(item?.title).toBe('Redacted Title')
    expect(item?.anchor).toEqual({ type: 'untimed' })
    expect(item?.completion).toEqual({ type: 'open' })
    expect(item?.importance).toBe(1)
  })

  it('decodes a real event row, including a genuine EventKit-mirrored one with attendees + externalRef', () => {
    const item = decodeItemRow('event', JSON.stringify(fixtureEvent)) as EventItem | undefined
    expect(item?.kind).toBe('event')
    expect(item?.attendees).toEqual(['person1@example.com', 'person2@example.com'])
    expect(item?.externalRef?.source).toBe('eventKit')
    expect(item?.externalRef?.identifier).toContain('@google.com')
    // This is the exact bug class fixed natively this session — a decoded
    // EventKit mirror must be flagged as externally managed.
    expect(item && isExternallyManaged(item)).toBe(true)
  })

  it('decodes a real workout row, including the base64 exercise sub-blobs', () => {
    const item = decodeItemRow('workout', JSON.stringify(fixtureWorkout)) as WorkoutItem | undefined
    expect(item?.kind).toBe('workout')
    expect(item?.plannedExercises.length).toBeGreaterThan(0)
    expect(item?.plannedExercises[0]).toHaveProperty('exerciseID')
    expect(item?.plannedExercises[0]).toHaveProperty('sets')
    expect(item?.actualExercises?.length).toBeGreaterThan(0)
    expect(item?.actualExercises?.[0]).toHaveProperty('setsCompleted')
    expect(item?.actualKcal).toBe(300)
  })

  it('decodes a real meal row', () => {
    const item = decodeItemRow('meal', JSON.stringify(fixtureMeal)) as MealItem | undefined
    expect(item?.kind).toBe('meal')
    expect(item?.recipeID).toBe('r004')
    expect(item?.targetKcal).toBe(660)
    expect(item?.servings).toBe(1)
  })
})

describe('decodeItemRow resilience — the ~26 polluted/unknown rows must not crash sync', () => {
  it('returns undefined for an unrecognized kind rather than throwing', () => {
    expect(decodeItemRow('somethingFromAFutureBuild', '{}')).toBeUndefined()
  })

  it('returns undefined for malformed JSON rather than throwing', () => {
    expect(decodeItemRow('task', '{not valid json')).toBeUndefined()
  })
})

describe('decodeItemRow accepts both REST (string) and realtime (parsed object) shapes for `data`', () => {
  // Caught live during Phase 1's cross-client verification: a REST select()
  // returns `items.data` (jsonb) as a JSON string, but a realtime
  // postgres_changes payload for the identical row delivers it already
  // parsed into an object — a row that decoded fine on initial load
  // silently failed the moment the same data arrived via the websocket.
  it('decodes a string payload (REST shape)', () => {
    const item = decodeItemRow('task', JSON.stringify(fixtureTask))
    expect(item?.kind).toBe('task')
  })

  it('decodes an already-parsed object payload (realtime shape)', () => {
    const item = decodeItemRow('task', fixtureTask as unknown as Record<string, unknown>)
    expect(item?.kind).toBe('task')
    expect(item?.id).toBe('A2572F37-0475-4DA4-A67F-DC9F027EE038')
  })
})

describe('encode -> decode round-trip for every kind', () => {
  const base = {
    id: 'test-id-0000',
    title: 'Round trip test',
    notes: 'some notes',
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-01-02T00:00:00.000Z'),
    importance: 2,
    anchor: { type: 'dueAt', date: '2026-01-03T00:00:00.000Z' } as const,
    completion: { type: 'open' } as const,
  }

  it('task', () => {
    const item: TaskItem = { ...base, kind: 'task', tags: [{ id: 't1', name: 'work', colorRaw: 'blue' }] }
    const { kind, json } = encodeItemPayload(item)
    expect(decodeItemRow(kind, json)).toEqual(item)
  })

  it('event (native, no externalRef)', () => {
    const item: EventItem = { ...base, kind: 'event', tags: [], attendees: ['a@example.com'], location: 'Office' }
    const { kind, json } = encodeItemPayload(item)
    expect(decodeItemRow(kind, json)).toEqual(item)
  })

  it('reminder', () => {
    const item: ReminderItem = { ...base, kind: 'reminder', tags: [], leadTime: 900 }
    const { kind, json } = encodeItemPayload(item)
    expect(decodeItemRow(kind, json)).toEqual(item)
  })

  it('alarm', () => {
    const item: AlarmItem = { ...base, kind: 'alarm', tags: [], soundProfileRaw: 'alarm_default', escalates: true }
    const { kind, json } = encodeItemPayload(item)
    expect(decodeItemRow(kind, json)).toEqual(item)
  })

  it('habitInstance (no tags field)', () => {
    const { notes: _n, ...noNotesBase } = base
    const item: HabitInstanceItem = { ...noNotesBase, kind: 'habitInstance', habitID: 'habit-1' }
    const { kind, json } = encodeItemPayload(item)
    expect(decodeItemRow(kind, json)).toEqual(item)
  })

  it('workout with exercise sub-blobs', () => {
    const item: WorkoutItem = {
      ...base,
      kind: 'workout',
      tags: [],
      plannedExercises: [{ exerciseID: 'ex001', sets: 3, reps: 10 }],
      estimatedKcal: 250,
      actualExercises: [{ exerciseID: 'ex001', setsCompleted: 3, repsCompleted: 10, weightKg: 20 }],
      actualKcal: 260,
    }
    const { kind, json } = encodeItemPayload(item)
    expect(decodeItemRow(kind, json)).toEqual(item)
  })

  it('meal with macros', () => {
    const item: MealItem = {
      ...base,
      kind: 'meal',
      tags: [],
      recipeID: 'r001',
      servings: 2,
      targetKcal: 500,
      loggedMacros: { proteinG: 30, carbG: 40, fatG: 10 },
    }
    const { kind, json } = encodeItemPayload(item)
    expect(decodeItemRow(kind, json)).toEqual(item)
  })
})

describe('isExternallyManaged', () => {
  it('is false for a native task/workout/meal (no externalRef concept)', () => {
    const task = decodeItemRow('task', JSON.stringify(fixtureTask))!
    expect(isExternallyManaged(task)).toBe(false)
  })
})
