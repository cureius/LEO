import { registerTool } from '../toolRuntime'
import { useSyncStore } from '@/sync/store'
import type { DiffChange, DiffPayload, PendingNewItem } from '../diff/types'

/**
 * Direct port of ProposeTools.swift's propose_reschedule/propose_add/
 * propose_cancel. These never touch the store — they only ever build a
 * DiffPayload for user review (diff/applyDiff.ts is the only thing that
 * writes, and only once the user accepts). This is the load-bearing
 * guarantee carried over from Swift: the AI never writes directly, ever.
 */

registerTool(
  {
    name: 'propose_reschedule',
    description: 'Propose rescheduling one or more items. Returns a Diff for user review — does NOT apply changes.',
    input_schema: {
      type: 'object',
      properties: {
        items: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              id: { type: 'string' },
              newStart: { type: 'string', description: 'ISO8601 datetime with timezone offset' },
              newEnd: { type: 'string', description: 'ISO8601 datetime with timezone offset; omit for non-blocks' },
            },
            required: ['id', 'newStart'],
          },
        },
        rationale: { type: 'string' },
      },
      required: ['items', 'rationale'],
    },
  },
  async (input) => {
    const { items, rationale } = input as { items: { id: string; newStart: string; newEnd?: string }[]; rationale: string }
    const changes: DiffChange[] = items.map((r) => {
      const newValue = r.newEnd ? `timeBlock:${r.newStart}–${r.newEnd}` : `point:${r.newStart}`
      return { itemID: r.id, kind: 'update', field: 'anchor', newValue }
    })
    return { changes, rationale } satisfies DiffPayload
  },
)

registerTool(
  {
    name: 'propose_add',
    description: 'Propose adding one or more new tasks, events, or reminders. Returns a Diff for user review — does NOT create items immediately.',
    input_schema: {
      type: 'object',
      properties: {
        items: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              title: { type: 'string' },
              type: { type: 'string', enum: ['task', 'event', 'reminder'] },
              start: { type: 'string', description: 'ISO8601 datetime WITH timezone offset. Never omit the offset.' },
              end: { type: 'string', description: 'ISO8601 datetime with timezone offset for block/event end.' },
              notes: { type: 'string' },
            },
            required: ['title', 'type'],
          },
        },
        rationale: { type: 'string' },
      },
      required: ['items', 'rationale'],
    },
  },
  async (input) => {
    const { items, rationale } = input as { items: PendingNewItem[]; rationale: string }
    const changes: DiffChange[] = items.map((item) => ({
      itemID: crypto.randomUUID(),
      kind: 'add',
      field: 'title',
      newValue: item.title,
      pendingItem: item,
    }))
    return { changes, rationale } satisfies DiffPayload
  },
)

registerTool(
  {
    name: 'propose_cancel',
    description: 'Propose deleting or cancelling items. Returns a Diff for user review.',
    input_schema: {
      type: 'object',
      properties: { ids: { type: 'array', items: { type: 'string' } }, rationale: { type: 'string' } },
      required: ['ids', 'rationale'],
    },
  },
  async (input) => {
    const { ids, rationale } = input as { ids: string[]; rationale: string }
    const store = useSyncStore.getState()
    const changes: DiffChange[] = ids.map((id) => {
      const title = store.getItem(id)?.title ?? 'Unknown item'
      return { itemID: id, kind: 'delete', field: 'title', newValue: title }
    })
    return { changes, rationale } satisfies DiffPayload
  },
)
