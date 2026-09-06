import { describe, expect, it } from 'vitest'
import { computeDashboardStats } from '../dashboardStats'
import type { DomainItem, EventItem, Habit, HabitInstanceItem, TaskItem } from '@/domain/types'

// Local-time construction throughout this file (no 'Z'/offset suffix on any
// date used for same-day comparisons) — computeDashboardStats buckets days
// using local getFullYear/Month/Date, so a UTC-anchored `now` would make
// the "today" assertions below flaky depending on the test runner's TZ.
const now = new Date(2026, 6, 29, 12, 0, 0)

function task(overrides: Partial<TaskItem>): TaskItem {
  return {
    id: 'x',
    title: 'x',
    createdAt: now,
    updatedAt: now,
    importance: 1,
    tags: [],
    kind: 'task',
    anchor: { type: 'untimed' },
    completion: { type: 'open' },
    ...overrides,
  }
}

describe('computeDashboardStats', () => {
  it('counts open items and excludes habit instances from the base counts', () => {
    const items: DomainItem[] = [
      task({ id: '1' }),
      task({ id: '2', completion: { type: 'completed', date: now.toISOString() } }),
      { id: '3', title: 'h', createdAt: now, updatedAt: now, importance: 1, kind: 'habitInstance', habitID: 'H', anchor: { type: 'untimed' }, completion: { type: 'open' } } as HabitInstanceItem,
    ]
    const stats = computeDashboardStats(items, [], now)
    expect(stats.openCount).toBe(1)
  })

  it('flags an open item with a past sortDate as overdue', () => {
    const items: DomainItem[] = [task({ id: '1', anchor: { type: 'dueAt', date: '2026-07-01T00:00:00Z' } })]
    const stats = computeDashboardStats(items, [], now)
    expect(stats.overdueCount).toBe(1)
  })

  it('does not flag a future-dated open item as overdue', () => {
    const items: DomainItem[] = [task({ id: '1', anchor: { type: 'dueAt', date: '2026-08-15T00:00:00Z' } })]
    const stats = computeDashboardStats(items, [], now)
    expect(stats.overdueCount).toBe(0)
  })

  it('counts completions within the last 7 days for completedThisWeek', () => {
    const items: DomainItem[] = [
      task({ id: '1', completion: { type: 'completed', date: new Date(2026, 6, 28).toISOString() } }),
      task({ id: '2', completion: { type: 'completed', date: new Date(2026, 5, 1).toISOString() } }),
    ]
    const stats = computeDashboardStats(items, [], now)
    expect(stats.completedThisWeek).toBe(1)
  })

  it('computes a 100% completion rate when everything due in the window was completed', () => {
    const items: DomainItem[] = [
      task({ id: '1', anchor: { type: 'dueAt', date: new Date(2026, 6, 20).toISOString() }, completion: { type: 'completed', date: new Date(2026, 6, 20).toISOString() } }),
    ]
    const stats = computeDashboardStats(items, [], now)
    expect(stats.completionRate30d).toBe(100)
  })

  it('produces one entry per day from the start of the month through today', () => {
    const stats = computeDashboardStats([], [], now)
    expect(stats.completionsByDay).toHaveLength(29)
    expect(stats.completionsByDay[0].date).toBe(new Date(2026, 6, 1).toDateString())
    expect(stats.completionsByDay[28].date).toBe(new Date(2026, 6, 29).toDateString())
  })

  it('produces 7 entries for scheduledHoursByDay starting today, summing timeBlock durations', () => {
    const items: DomainItem[] = [
      task({ id: '1', anchor: { type: 'timeBlock', start: '2026-07-29T09:00:00', end: '2026-07-29T11:00:00' } }),
    ]
    const stats = computeDashboardStats(items, [], now)
    expect(stats.scheduledHoursByDay).toHaveLength(7)
    expect(stats.scheduledHoursByDay[0].hours).toBe(2)
  })

  it('groups open items by project tag, sorted descending, capped at 8', () => {
    const items: DomainItem[] = [
      task({ id: '1', tags: [{ id: 't1', name: 'Office', colorRaw: 'blue' }] }),
      task({ id: '2', tags: [{ id: 't2', name: 'Office', colorRaw: 'blue' }] }),
      task({ id: '3', tags: [{ id: 't3', name: 'Home', colorRaw: 'green' }] }),
    ]
    const stats = computeDashboardStats(items, [], now)
    expect(stats.byProject[0]).toEqual({ name: 'Office', color: 'blue', openCount: 2, totalCount: 2, completedCount: 0, completionRate: 0 })
    expect(stats.byProject[1]).toEqual({ name: 'Home', color: 'green', openCount: 1, totalCount: 1, completedCount: 0, completionRate: 0 })
  })

  it('a completed item does not count toward its project open count, but still counts toward completion rate', () => {
    const items: DomainItem[] = [task({ id: '1', tags: [{ id: 't1', name: 'Office', colorRaw: 'blue' }], completion: { type: 'completed', date: now.toISOString() } })]
    const stats = computeDashboardStats(items, [], now)
    expect(stats.byProject).toEqual([{ name: 'Office', color: 'blue', openCount: 0, totalCount: 1, completedCount: 1, completionRate: 100 }])
  })

  it('breaks open items down by kind', () => {
    const event: EventItem = { ...task({ id: '1' }), kind: 'event', attendees: [] }
    const items: DomainItem[] = [task({ id: '2' }), event]
    const stats = computeDashboardStats(items, [], now)
    expect(stats.byKind).toEqual(expect.arrayContaining([{ kind: 'task', count: 1 }, { kind: 'event', count: 1 }]))
  })

  it('reports active (non-archived) habit count and best streak', () => {
    const habits: Habit[] = [
      { id: 'H1', name: 'Read', frequency: { type: 'daily' }, forgiveness: { type: 'none' }, recurrenceRuleRaw: 'FREQ=DAILY', createdAt: now, isArchived: false },
      { id: 'H2', name: 'Old', frequency: { type: 'daily' }, forgiveness: { type: 'none' }, recurrenceRuleRaw: 'FREQ=DAILY', createdAt: now, isArchived: true },
    ]
    const instance: HabitInstanceItem = {
      id: 'i1', title: 'Read', createdAt: now, updatedAt: now, importance: 1, kind: 'habitInstance', habitID: 'H1',
      anchor: { type: 'dueAt', date: now.toISOString() }, completion: { type: 'completed', date: now.toISOString() },
    }
    const stats = computeDashboardStats([instance], habits, now)
    expect(stats.activeHabitCount).toBe(1)
    expect(stats.bestStreak).toBeGreaterThanOrEqual(1)
  })
})
