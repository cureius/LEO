import { describe, expect, it, vi, beforeEach } from 'vitest'
import type { DomainItem, Habit, HabitInstanceItem } from '@/domain/types'

const addItemMock = vi.fn()
let storeItems: DomainItem[] = []

vi.mock('@/sync/mutations', () => ({ addItem: (item: DomainItem) => addItemMock(item) }))
vi.mock('@/sync/store', () => ({
  useSyncStore: { getState: () => ({}) },
  selectItemsArray: () => storeItems,
}))

const { materializeHabit } = await import('../habitMaterializer')

function habit(overrides: Partial<Habit> = {}): Habit {
  return {
    id: 'habit-1',
    name: 'Morning run',
    frequency: { type: 'daily' },
    forgiveness: { type: 'none' },
    recurrenceRuleRaw: 'FREQ=DAILY',
    createdAt: new Date(),
    isArchived: false,
    ...overrides,
  }
}

function existingInstance(habitID: string, date: Date, completion: HabitInstanceItem['completion'] = { type: 'open' }): HabitInstanceItem {
  return {
    kind: 'habitInstance',
    id: crypto.randomUUID(),
    title: 'x',
    createdAt: date,
    updatedAt: date,
    importance: 1,
    anchor: { type: 'point', date: date.toISOString() },
    completion,
    habitID,
    targetDurationSeconds: undefined,
  }
}

beforeEach(() => {
  addItemMock.mockClear()
  storeItems = []
})

describe('materializeHabit', () => {
  it('creates a new habitInstance for each occurrence when none exist yet', async () => {
    const h = habit({ createdAt: new Date(2026, 6, 1) })
    await materializeHabit(h)
    // 14-day rolling window from today -> at least one call, one per day for a daily habit.
    expect(addItemMock).toHaveBeenCalled()
    const firstCall = addItemMock.mock.calls[0][0] as HabitInstanceItem
    expect(firstCall.kind).toBe('habitInstance')
    expect(firstCall.habitID).toBe('habit-1')
    expect(firstCall.completion).toEqual({ type: 'open' })
  })

  it('skips a day that already has an OPEN instance — idempotent, never duplicates', async () => {
    const h = habit({ createdAt: new Date(2026, 6, 1) })
    const today = new Date()
    storeItems = [existingInstance('habit-1', today, { type: 'open' })]
    await materializeHabit(h)
    const calledForToday = addItemMock.mock.calls.some((call) => {
      const item = call[0] as HabitInstanceItem
      return new Date(item.anchor.type === 'point' ? item.anchor.date : item.createdAt).toDateString() === today.toDateString()
    })
    expect(calledForToday).toBe(false)
  })

  it('skips a day that already has a COMPLETED instance — never touches a resolved instance', async () => {
    const h = habit({ createdAt: new Date(2026, 6, 1) })
    const today = new Date()
    storeItems = [existingInstance('habit-1', today, { type: 'completed', date: today.toISOString() })]
    await materializeHabit(h)
    const calledForToday = addItemMock.mock.calls.some((call) => {
      const item = call[0] as HabitInstanceItem
      return new Date(item.anchor.type === 'point' ? item.anchor.date : item.createdAt).toDateString() === today.toDateString()
    })
    expect(calledForToday).toBe(false)
  })

  it('ignores instances belonging to a DIFFERENT habit when deduping', async () => {
    const h = habit({ id: 'habit-1', createdAt: new Date(2026, 6, 1) })
    const today = new Date()
    storeItems = [existingInstance('some-other-habit', today, { type: 'open' })]
    await materializeHabit(h)
    // Should still materialize today's instance for habit-1 — the existing
    // instance belongs to a different habit and must not suppress it.
    const calledForHabit1Today = addItemMock.mock.calls.some((call) => (call[0] as HabitInstanceItem).habitID === 'habit-1')
    expect(calledForHabit1Today).toBe(true)
  })

  it('builds a .point anchor when the habit has no targetDuration', async () => {
    const h = habit({ createdAt: new Date(2026, 6, 1), targetDurationSeconds: undefined })
    await materializeHabit(h)
    const item = addItemMock.mock.calls[0][0] as HabitInstanceItem
    expect(item.anchor.type).toBe('point')
  })

  it('builds a .timeBlock anchor when the habit has a targetDuration', async () => {
    const h = habit({ createdAt: new Date(2026, 6, 1), targetDurationSeconds: 1800 })
    await materializeHabit(h)
    const item = addItemMock.mock.calls[0][0] as HabitInstanceItem
    expect(item.anchor.type).toBe('timeBlock')
    if (item.anchor.type === 'timeBlock') {
      const durationMs = new Date(item.anchor.end).getTime() - new Date(item.anchor.start).getTime()
      expect(durationMs).toBe(1800 * 1000)
    }
  })

  it('uses hour 7 for morning, 13 for afternoon, 19 for evening — port of TimeOfDay.hintHour', async () => {
    // Assert on the LOCAL hour the code actually constructs (`new Date(y, m, d,
    // hour, ...)`), not a hardcoded UTC offset — a fixed "T01:30:00Z"-style
    // assertion would only hold in one specific timezone (IST) and silently
    // break in CI or for any other contributor's machine.
    for (const [hint, expectedHour] of [
      ['morning', 7],
      ['afternoon', 13],
      ['evening', 19],
    ] as const) {
      addItemMock.mockClear()
      storeItems = []
      await materializeHabit(habit({ createdAt: new Date(2026, 6, 1), timeHint: { type: hint } }))
      const item = addItemMock.mock.calls[0][0] as HabitInstanceItem
      const anchorDate = item.anchor.type === 'point' ? new Date(item.anchor.date) : new Date()
      expect(anchorDate.getHours()).toBe(expectedHour)
    }
  })

  it('uses an explicit hour/minute for a `specific` time hint', async () => {
    const h = habit({ createdAt: new Date(2026, 6, 1), timeHint: { type: 'specific', hour: 6, minute: 45 } })
    await materializeHabit(h)
    const item = addItemMock.mock.calls[0][0] as HabitInstanceItem
    const anchorDate = item.anchor.type === 'point' ? new Date(item.anchor.date) : new Date()
    expect(anchorDate.getHours()).toBe(6)
    expect(anchorDate.getMinutes()).toBe(45)
  })
})
