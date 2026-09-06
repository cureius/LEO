import { describe, expect, it, beforeEach } from 'vitest'
import '../tools/readTools' // registers get_today/get_week/find_free_slots/get_item
import { executeTool } from '../toolRuntime'
import { useSyncStore } from '@/sync/store'
import type { TaskItem, WorkoutItem } from '@/domain/types'

function task(id: string, overrides: Partial<TaskItem> = {}): TaskItem {
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
    ...overrides,
  }
}

beforeEach(() => {
  useSyncStore.setState({ items: new Map() })
})

describe('get_today — regression: untimed items were completely invisible to the AI', () => {
  it('includes items scheduled for today', async () => {
    const store = useSyncStore.getState()
    store.upsertItem(task('due-today', { anchor: { type: 'dueAt', date: new Date().toISOString() } }))

    const { result } = await executeTool('get_today', '{}')
    const items = JSON.parse(result)
    expect(items.map((i: { id: string }) => i.id)).toContain('due-today')
  })

  it('also includes the entire untimed backlog — matches TodayPage.tsx, which merges it in alongside today\'s schedule', async () => {
    const store = useSyncStore.getState()
    store.upsertItem(task('untimed-open', { anchor: { type: 'untimed' } }))

    const { result } = await executeTool('get_today', '{}')
    const items = JSON.parse(result)
    expect(items.map((i: { id: string }) => i.id)).toContain('untimed-open')
  })

  it('excludes an untimed item that is already completed — only the open backlog surfaces, matching TodayPage', async () => {
    const store = useSyncStore.getState()
    store.upsertItem(task('untimed-done', { anchor: { type: 'untimed' }, completion: { type: 'completed', date: new Date().toISOString() } }))

    const { result } = await executeTool('get_today', '{}')
    const items = JSON.parse(result)
    expect(items.map((i: { id: string }) => i.id)).not.toContain('untimed-done')
  })

  it('excludes an item scheduled for a different day', async () => {
    const store = useSyncStore.getState()
    const nextWeek = new Date(Date.now() + 10 * 86_400_000).toISOString()
    store.upsertItem(task('next-week', { anchor: { type: 'dueAt', date: nextWeek } }))

    const { result } = await executeTool('get_today', '{}')
    const items = JSON.parse(result)
    expect(items.map((i: { id: string }) => i.id)).not.toContain('next-week')
  })
})

describe('get_week', () => {
  it('includes an item due in 3 days but NOT an untimed item — get_week has no backlog merge (that is get_today\'s job)', async () => {
    const store = useSyncStore.getState()
    const in3Days = new Date(Date.now() + 3 * 86_400_000).toISOString()
    store.upsertItem(task('in-3-days', { anchor: { type: 'dueAt', date: in3Days } }))
    store.upsertItem(task('untimed', { anchor: { type: 'untimed' } }))

    const { result } = await executeTool('get_week', '{}')
    const ids = JSON.parse(result).map((i: { id: string }) => i.id)
    expect(ids).toContain('in-3-days')
    expect(ids).not.toContain('untimed')
  })
})

describe('get_past_items — regression: no tool could see anything before today, even completed items', () => {
  it('includes an item from 3 days ago', async () => {
    const store = useSyncStore.getState()
    const threeDaysAgo = new Date(Date.now() - 3 * 86_400_000).toISOString()
    store.upsertItem(task('past-3d', { anchor: { type: 'dueAt', date: threeDaysAgo }, completion: { type: 'completed', date: threeDaysAgo } }))

    const { result } = await executeTool('get_past_items', '{}')
    const ids = JSON.parse(result).map((i: { id: string }) => i.id)
    expect(ids).toContain('past-3d')
  })

  it('excludes today and the future', async () => {
    const store = useSyncStore.getState()
    store.upsertItem(task('today', { anchor: { type: 'dueAt', date: new Date().toISOString() } }))
    const tomorrow = new Date(Date.now() + 86_400_000).toISOString()
    store.upsertItem(task('tomorrow', { anchor: { type: 'dueAt', date: tomorrow } }))

    const { result } = await executeTool('get_past_items', '{}')
    const ids = JSON.parse(result).map((i: { id: string }) => i.id)
    expect(ids).not.toContain('today')
    expect(ids).not.toContain('tomorrow')
  })

  it('defaults to a 7-day lookback, excluding something 10 days ago', async () => {
    const store = useSyncStore.getState()
    const tenDaysAgo = new Date(Date.now() - 10 * 86_400_000).toISOString()
    store.upsertItem(task('past-10d', { anchor: { type: 'dueAt', date: tenDaysAgo } }))

    const { result } = await executeTool('get_past_items', '{}')
    const ids = JSON.parse(result).map((i: { id: string }) => i.id)
    expect(ids).not.toContain('past-10d')
  })

  it('respects an explicit `days` param to look further back', async () => {
    const store = useSyncStore.getState()
    const tenDaysAgo = new Date(Date.now() - 10 * 86_400_000).toISOString()
    store.upsertItem(task('past-10d', { anchor: { type: 'dueAt', date: tenDaysAgo } }))

    const { result } = await executeTool('get_past_items', JSON.stringify({ days: 14 }))
    const ids = JSON.parse(result).map((i: { id: string }) => i.id)
    expect(ids).toContain('past-10d')
  })

  it('includes still-open (missed) past items, not just completed ones', async () => {
    const store = useSyncStore.getState()
    const twoDaysAgo = new Date(Date.now() - 2 * 86_400_000).toISOString()
    store.upsertItem(task('missed', { anchor: { type: 'dueAt', date: twoDaysAgo }, completion: { type: 'open' } }))

    const { result } = await executeTool('get_past_items', '{}')
    const items = JSON.parse(result) as { id: string; completed: boolean }[]
    expect(items.find((i) => i.id === 'missed')?.completed).toBe(false)
  })

  it('returns most-recent-first', async () => {
    const store = useSyncStore.getState()
    store.upsertItem(task('older', { anchor: { type: 'dueAt', date: new Date(Date.now() - 5 * 86_400_000).toISOString() } }))
    store.upsertItem(task('newer', { anchor: { type: 'dueAt', date: new Date(Date.now() - 1 * 86_400_000).toISOString() } }))

    const { result } = await executeTool('get_past_items', '{}')
    const ids = JSON.parse(result).map((i: { id: string }) => i.id)
    expect(ids.indexOf('newer')).toBeLessThan(ids.indexOf('older'))
  })
})

describe('get_item', () => {
  it('summarizes a workout item correctly by id', async () => {
    const workout: WorkoutItem = {
      kind: 'workout',
      id: 'w1',
      title: 'Leg day',
      createdAt: new Date(),
      updatedAt: new Date(),
      importance: 1,
      anchor: { type: 'untimed' },
      completion: { type: 'open' },
      tags: [],
      plannedExercises: [],
      estimatedKcal: 300,
    }
    useSyncStore.getState().upsertItem(workout)
    const { result } = await executeTool('get_item', JSON.stringify({ id: 'w1' }))
    expect(JSON.parse(result)).toMatchObject({ id: 'w1', kind: 'workout', title: 'Leg day' })
  })

  it('returns an error object, not a thrown exception, for an unknown id', async () => {
    const { result, isError } = await executeTool('get_item', JSON.stringify({ id: 'nope' }))
    expect(isError).toBe(false)
    expect(JSON.parse(result)).toEqual({ error: 'Item not found' })
  })
})
