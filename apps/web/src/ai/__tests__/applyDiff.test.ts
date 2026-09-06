import { describe, expect, it, vi, beforeEach } from 'vitest'
import type { DomainItem, TaskItem, WorkoutItem } from '@/domain/types'
import type { DiffChange } from '../diff/types'

const addItemMock = vi.fn()
const updateItemMock = vi.fn()
const deleteItemMock = vi.fn()
let storeItems = new Map<string, DomainItem>()

vi.mock('@/sync/mutations', () => ({
  addItem: (item: DomainItem) => addItemMock(item),
  updateItem: (item: DomainItem) => updateItemMock(item),
  deleteItem: (item: DomainItem) => deleteItemMock(item),
}))
vi.mock('@/sync/store', () => ({
  useSyncStore: { getState: () => ({ getItem: (id: string) => storeItems.get(id) }) },
}))

const { applyDiffChanges } = await import('../diff/applyDiff')

function existingTask(id: string): TaskItem {
  return {
    kind: 'task', id, title: 'Existing', createdAt: new Date(), updatedAt: new Date(),
    importance: 1, anchor: { type: 'untimed' }, completion: { type: 'open' }, tags: [],
  }
}
function existingWorkout(id: string, overrides: Partial<WorkoutItem> = {}): WorkoutItem {
  return {
    kind: 'workout', id, title: 'Push Day', createdAt: new Date(), updatedAt: new Date(),
    importance: 1, anchor: { type: 'untimed' }, completion: { type: 'open' }, tags: [],
    plannedExercises: [], estimatedKcal: 0, ...overrides,
  }
}

beforeEach(() => {
  addItemMock.mockClear()
  updateItemMock.mockClear()
  deleteItemMock.mockClear()
  storeItems = new Map()
})

describe('applyDiffChanges — the only place a proposed AI change can reach the store', () => {
  it('an "add" change with a pendingItem calls addItem with a freshly-built item', async () => {
    const change: DiffChange = { itemID: 'ignored', kind: 'add', field: 'title', newValue: 'Buy milk', pendingItem: { title: 'Buy milk', type: 'task' } }
    await applyDiffChanges([change])
    expect(addItemMock).toHaveBeenCalledTimes(1)
    const built = addItemMock.mock.calls[0][0] as TaskItem
    expect(built.kind).toBe('task')
    expect(built.title).toBe('Buy milk')
    expect(built.anchor).toEqual({ type: 'untimed' })
  })

  it('an "add" with start but no end builds a dueAt anchor', async () => {
    const change: DiffChange = { itemID: 'x', kind: 'add', field: 'title', newValue: 'x', pendingItem: { title: 'x', type: 'task', start: '2026-07-19T09:00:00Z' } }
    await applyDiffChanges([change])
    const built = addItemMock.mock.calls[0][0] as TaskItem
    expect(built.anchor).toEqual({ type: 'dueAt', date: '2026-07-19T09:00:00Z' })
  })

  it('an "add" with start AND end builds a timeBlock anchor', async () => {
    const change: DiffChange = { itemID: 'x', kind: 'add', field: 'title', newValue: 'x', pendingItem: { title: 'x', type: 'event', start: '2026-07-19T09:00:00Z', end: '2026-07-19T10:00:00Z' } }
    await applyDiffChanges([change])
    const built = addItemMock.mock.calls[0][0]
    expect(built.anchor).toEqual({ type: 'timeBlock', start: '2026-07-19T09:00:00Z', end: '2026-07-19T10:00:00Z' })
  })

  it('an "add" workout with pendingItem.exercises builds real plannedExercises, not an empty array', async () => {
    await applyDiffChanges([{
      itemID: 'x', kind: 'add', field: 'title', newValue: 'x',
      pendingItem: {
        title: 'Push day', type: 'workout',
        exercises: [{ name: 'Bench Press', sets: 4, reps: 8 }, { name: 'OHP', sets: 3, reps: 10, weightKg: 40 }],
        estimatedKcal: 300,
      },
    }])
    const built = addItemMock.mock.calls[0][0] as DomainItem & { plannedExercises: unknown; estimatedKcal: number }
    expect(built.plannedExercises).toEqual([
      { exerciseID: 'Bench Press', sets: 4, reps: 8 },
      { exerciseID: 'OHP', sets: 3, reps: 10, weightKg: 40 },
    ])
    expect(built.estimatedKcal).toBe(300)
  })

  it('an "add" with pendingItem.type "workout"/"meal" builds the right kind — confirmed wider than task/event/reminder', async () => {
    await applyDiffChanges([{ itemID: 'x', kind: 'add', field: 'title', newValue: 'x', pendingItem: { title: 'Push day', type: 'workout' } }])
    expect((addItemMock.mock.calls[0][0] as DomainItem).kind).toBe('workout')
  })

  it('an "update" with field "anchor" and a timeBlock-formatted value updates the item\'s anchor', async () => {
    storeItems.set('item-1', existingTask('item-1'))
    await applyDiffChanges([{ itemID: 'item-1', kind: 'update', field: 'anchor', newValue: 'timeBlock:2026-07-19T09:00:00Z–2026-07-19T10:00:00Z' }])
    expect(updateItemMock).toHaveBeenCalledTimes(1)
    const updated = updateItemMock.mock.calls[0][0] as TaskItem
    expect(updated.anchor).toEqual({ type: 'timeBlock', start: '2026-07-19T09:00:00Z', end: '2026-07-19T10:00:00Z' })
  })

  it('an "update" with field "anchor" and a point-formatted value updates the item\'s anchor', async () => {
    storeItems.set('item-1', existingTask('item-1'))
    await applyDiffChanges([{ itemID: 'item-1', kind: 'update', field: 'anchor', newValue: 'point:2026-07-19T09:00:00Z' }])
    const updated = updateItemMock.mock.calls[0][0] as TaskItem
    expect(updated.anchor).toEqual({ type: 'point', date: '2026-07-19T09:00:00Z' })
  })

  it('an "update" with field "notes" sets notes on the existing item, preserving other fields', async () => {
    storeItems.set('item-1', existingTask('item-1'))
    await applyDiffChanges([{ itemID: 'item-1', kind: 'update', field: 'notes', newValue: 'swap for oats' }])
    const updated = updateItemMock.mock.calls[0][0] as TaskItem
    expect(updated.notes).toBe('swap for oats')
    expect(updated.title).toBe('Existing') // untouched
  })

  it('an "update" with field "workoutDetail" sets plannedExercises and estimatedKcal on a workout item (set_workout_exercises)', async () => {
    storeItems.set('w-1', existingWorkout('w-1'))
    const exercises = [{ exerciseID: 'Bench Press', sets: 4, reps: 8 }, { exerciseID: 'OHP', sets: 3, reps: 10, weightKg: 40 }]
    await applyDiffChanges([
      { itemID: 'w-1', kind: 'update', field: 'workoutDetail', newValue: JSON.stringify({ exercises, estimatedKcal: 350 }) },
    ])
    const updated = updateItemMock.mock.calls[0][0] as WorkoutItem
    expect(updated.plannedExercises).toEqual(exercises)
    expect(updated.estimatedKcal).toBe(350)
  })

  it('"workoutDetail" without estimatedKcal leaves the item\'s existing estimatedKcal untouched', async () => {
    storeItems.set('w-1', existingWorkout('w-1', { estimatedKcal: 300 }))
    await applyDiffChanges([
      { itemID: 'w-1', kind: 'update', field: 'workoutDetail', newValue: JSON.stringify({ exercises: [{ exerciseID: 'Squat', sets: 5, reps: 5 }] }) },
    ])
    const updated = updateItemMock.mock.calls[0][0] as WorkoutItem
    expect(updated.estimatedKcal).toBe(300)
  })

  it('"workoutDetail" on a non-workout item is a no-op, not a crash', async () => {
    storeItems.set('item-1', existingTask('item-1'))
    await applyDiffChanges([
      { itemID: 'item-1', kind: 'update', field: 'workoutDetail', newValue: JSON.stringify({ exercises: [] }) },
    ])
    expect(updateItemMock).not.toHaveBeenCalled()
  })

  it('a "delete" change calls deleteItem with the real item looked up from the store', async () => {
    storeItems.set('item-1', existingTask('item-1'))
    await applyDiffChanges([{ itemID: 'item-1', kind: 'delete', field: 'title', newValue: 'Existing' }])
    expect(deleteItemMock).toHaveBeenCalledWith(storeItems.get('item-1'))
  })

  it('an "update"/"delete" for an id no longer in the store is a silent no-op, not a crash', async () => {
    await expect(applyDiffChanges([{ itemID: 'gone', kind: 'update', field: 'notes', newValue: 'x' }])).resolves.toEqual({ failures: [] })
    await expect(applyDiffChanges([{ itemID: 'gone', kind: 'delete', field: 'title', newValue: 'x' }])).resolves.toEqual({ failures: [] })
    expect(updateItemMock).not.toHaveBeenCalled()
    expect(deleteItemMock).not.toHaveBeenCalled()
  })

  it('a change that throws (e.g. deleteItem rejecting an EventKit-mirrored item) is reported as a failure, not thrown — and later changes in the same batch still run', async () => {
    storeItems.set('item-1', existingTask('item-1'))
    storeItems.set('item-2', existingTask('item-2'))
    deleteItemMock.mockImplementationOnce(() => {
      throw new Error('Cannot delete an item synced from Calendar/Reminders here.')
    })
    const { failures } = await applyDiffChanges([
      { itemID: 'item-1', kind: 'delete', field: 'title', newValue: 'Existing' },
      { itemID: 'item-2', kind: 'delete', field: 'title', newValue: 'Existing' },
    ])
    expect(failures).toHaveLength(1)
    expect(failures[0].message).toContain('Calendar/Reminders')
    expect(deleteItemMock).toHaveBeenCalledTimes(2) // the second delete still ran despite the first throwing
  })

  it('applies multiple changes of different kinds in one call, in order', async () => {
    storeItems.set('item-1', existingTask('item-1'))
    await applyDiffChanges([
      { itemID: 'x', kind: 'add', field: 'title', newValue: 'New', pendingItem: { title: 'New', type: 'task' } },
      { itemID: 'item-1', kind: 'delete', field: 'title', newValue: 'Existing' },
    ])
    expect(addItemMock).toHaveBeenCalledTimes(1)
    expect(deleteItemMock).toHaveBeenCalledTimes(1)
  })
})
