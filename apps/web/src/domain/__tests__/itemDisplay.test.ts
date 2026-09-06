import { describe, expect, it } from 'vitest'
import { completionIconFor, secondaryLineFor, kindLabel } from '../itemDisplay'
import type { AlarmItem, EventItem, MealItem, TaskItem, WorkoutItem } from '@/domain/types'

const base = {
  id: 'x', title: 'x', createdAt: new Date(), updatedAt: new Date(), importance: 1, tags: [],
}

describe('completionIconFor — port of ItemRow.swift completionIcon', () => {
  it('alarm: bell open, bellOff done', () => {
    const alarm: AlarmItem = { ...base, kind: 'alarm', anchor: { type: 'untimed' }, completion: { type: 'open' }, soundProfileRaw: 'alarm_default', escalates: false }
    expect(completionIconFor(alarm)).toBe('bell')
    expect(completionIconFor({ ...alarm, completion: { type: 'completed', date: 'x' } })).toBe('bellOff')
  })

  it('event: calendar open, calendarCheck done', () => {
    const event: EventItem = { ...base, kind: 'event', anchor: { type: 'untimed' }, completion: { type: 'open' }, attendees: [] }
    expect(completionIconFor(event)).toBe('calendar')
    expect(completionIconFor({ ...event, completion: { type: 'completed', date: 'x' } })).toBe('calendarCheck')
  })

  it('task/reminder default to circle/checkCircle', () => {
    const task: TaskItem = { ...base, kind: 'task', anchor: { type: 'untimed' }, completion: { type: 'open' } }
    expect(completionIconFor(task)).toBe('circle')
    expect(completionIconFor({ ...task, completion: { type: 'completed', date: 'x' } })).toBe('checkCircle')
  })
})

describe('secondaryLineFor — port of ItemRow.swift secondaryParts', () => {
  it('dueAt renders a relative time', () => {
    const now = new Date(2026, 0, 1, 10, 0)
    const task: TaskItem = { ...base, kind: 'task', anchor: { type: 'dueAt', date: new Date(2026, 0, 1, 12, 0).toISOString() }, completion: { type: 'open' } }
    expect(secondaryLineFor(task, now)).toBe('Due in 2h')
  })

  it('timeBlock renders a time range', () => {
    const task: TaskItem = { ...base, kind: 'task', anchor: { type: 'timeBlock', start: new Date(2026, 0, 1, 9, 0).toISOString(), end: new Date(2026, 0, 1, 10, 0).toISOString() }, completion: { type: 'open' } }
    expect(secondaryLineFor(task)).toContain('–')
  })

  it('event appends location', () => {
    const event: EventItem = { ...base, kind: 'event', anchor: { type: 'untimed' }, completion: { type: 'open' }, attendees: [], location: 'Office' }
    expect(secondaryLineFor(event)).toBe('· Office')
  })

  it('workout appends estimated kcal', () => {
    const w: WorkoutItem = { ...base, kind: 'workout', anchor: { type: 'untimed' }, completion: { type: 'open' }, plannedExercises: [], estimatedKcal: 250 }
    expect(secondaryLineFor(w)).toBe('· ~250 kcal')
  })

  it('meal prefers actualKcal over targetKcal when logged', () => {
    const m: MealItem = { ...base, kind: 'meal', anchor: { type: 'untimed' }, completion: { type: 'open' }, recipeID: 'r', servings: 1, targetKcal: 500, actualKcal: 480 }
    expect(secondaryLineFor(m)).toBe('· 480 kcal')
  })

  it('untimed item with nothing to show returns undefined', () => {
    const task: TaskItem = { ...base, kind: 'task', anchor: { type: 'untimed' }, completion: { type: 'open' } }
    expect(secondaryLineFor(task)).toBeUndefined()
  })
})

describe('kindLabel', () => {
  it('maps every kind to a human label', () => {
    expect(kindLabel('task')).toBe('Task')
    expect(kindLabel('habitInstance')).toBe('Habit')
  })
})
