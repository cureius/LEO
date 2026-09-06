import { describe, expect, it } from 'vitest'
import '../tools/proposeTools' // registers propose_reschedule/propose_add/propose_cancel
import { executeTool } from '../toolRuntime'
import { useSyncStore } from '@/sync/store'
import type { TaskItem } from '@/domain/types'

describe('propose_add', () => {
  it('builds an "add" DiffChange per item, carrying the full pendingItem — never touches the store', async () => {
    const before = useSyncStore.getState().items.size
    const { result, isError } = await executeTool(
      'propose_add',
      JSON.stringify({
        items: [{ title: 'Buy milk', type: 'task', start: '2026-07-19T09:00:00+05:30' }],
        rationale: 'You need milk',
      }),
    )
    expect(isError).toBe(false)
    const diff = JSON.parse(result)
    expect(diff.rationale).toBe('You need milk')
    expect(diff.changes).toHaveLength(1)
    expect(diff.changes[0].kind).toBe('add')
    expect(diff.changes[0].pendingItem).toEqual({ title: 'Buy milk', type: 'task', start: '2026-07-19T09:00:00+05:30' })
    // Non-negotiable: propose tools never write, even after building the diff.
    expect(useSyncStore.getState().items.size).toBe(before)
  })
})

describe('propose_reschedule', () => {
  it('formats a timeBlock reschedule as "timeBlock:<start>–<end>"', async () => {
    const { result } = await executeTool(
      'propose_reschedule',
      JSON.stringify({ items: [{ id: 'item-1', newStart: '2026-07-19T09:00:00+05:30', newEnd: '2026-07-19T10:00:00+05:30' }], rationale: 'r' }),
    )
    const diff = JSON.parse(result)
    expect(diff.changes[0]).toMatchObject({ itemID: 'item-1', kind: 'update', field: 'anchor', newValue: 'timeBlock:2026-07-19T09:00:00+05:30–2026-07-19T10:00:00+05:30' })
  })

  it('formats a point reschedule (no newEnd) as "point:<start>"', async () => {
    const { result } = await executeTool('propose_reschedule', JSON.stringify({ items: [{ id: 'item-1', newStart: '2026-07-19T09:00:00+05:30' }], rationale: 'r' }))
    const diff = JSON.parse(result)
    expect(diff.changes[0].newValue).toBe('point:2026-07-19T09:00:00+05:30')
  })
})

describe('propose_cancel', () => {
  it('looks up the real title of an item that exists in the store', async () => {
    const item: TaskItem = {
      kind: 'task', id: 'real-item', title: 'Dentist appointment', createdAt: new Date(), updatedAt: new Date(),
      importance: 1, anchor: { type: 'untimed' }, completion: { type: 'open' }, tags: [],
    }
    useSyncStore.getState().upsertItem(item)

    const { result } = await executeTool('propose_cancel', JSON.stringify({ ids: ['real-item'], rationale: 'r' }))
    const diff = JSON.parse(result)
    expect(diff.changes[0]).toMatchObject({ itemID: 'real-item', kind: 'delete', newValue: 'Dentist appointment' })
  })

  it('falls back to "Unknown item" for an id not in the store, rather than throwing', async () => {
    const { result, isError } = await executeTool('propose_cancel', JSON.stringify({ ids: ['does-not-exist'], rationale: 'r' }))
    expect(isError).toBe(false)
    expect(JSON.parse(result).changes[0].newValue).toBe('Unknown item')
  })
})
