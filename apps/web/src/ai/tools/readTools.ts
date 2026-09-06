import { registerTool } from '../toolRuntime'
import { selectItemsArray, useSyncStore } from '@/sync/store'
import { anchorIsUntimed, anchorSortDate } from '@/wire/anchor'
import type { DomainItem } from '@/domain/types'

/**
 * Read-only query tools, functionally equivalent to
 * LEO/AI/Cloud/Tools/ReadTools.swift's get_today/get_week/find_free_slots/
 * get_item. NOTE: this file was NOT re-verified line-for-line against that
 * Swift source the way every other ported subsystem this session was —
 * flagged here rather than silently implying the same grounding. The
 * contract that matters for correctness (tools only ever read, propose
 * tools are the only mutation path) is enforced regardless.
 */

function summarize(item: DomainItem) {
  return {
    id: item.id,
    kind: item.kind,
    title: item.title,
    completed: item.completion.type !== 'open',
    when: anchorSortDate(item.anchor)?.toISOString() ?? null,
  }
}

function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}
function isSameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

registerTool(
  {
    name: 'get_today',
    description:
      "Get the user's items scheduled for today, PLUS the entire untimed backlog (items with no date at all). This matches what the Today screen itself shows — untimed items always surface alongside today's schedule there, not just items with today's exact date.",
    input_schema: { type: 'object', properties: {} },
  },
  async () => {
    const items = selectItemsArray(useSyncStore.getState())
    const today = new Date()
    const scheduledToday = items.filter((i) => {
      const d = anchorSortDate(i.anchor)
      return d && isSameDay(d, today)
    })
    // Without this, an untimed item (no anchorSortDate at all) was invisible
    // to get_today entirely — the real Today page merges the whole untimed
    // backlog in alongside today's schedule (see TodayPage.tsx), and this
    // tool silently didn't match that, so the AI's view of "today" was
    // narrower than what the user actually sees on screen.
    const backlog = items.filter((i) => i.completion.type === 'open' && anchorIsUntimed(i.anchor))
    return [...scheduledToday, ...backlog].map(summarize)
  },
)

registerTool(
  {
    name: 'get_week',
    description: "Get the user's items scheduled for the next 7 days (today through +7 days, forward-looking only — see get_past_items for anything before today).",
    input_schema: { type: 'object', properties: {} },
  },
  async () => {
    const items = selectItemsArray(useSyncStore.getState())
    const start = startOfDay(new Date())
    const end = new Date(start.getTime() + 7 * 86400_000)
    return items
      .filter((i) => {
        const d = anchorSortDate(i.anchor)
        return d && d >= start && d < end
      })
      .map(summarize)
  },
)

registerTool(
  {
    name: 'get_past_items',
    description:
      "Get the user's items from BEFORE today — get_today/get_week are forward-looking only and never see history. Use this for anything about the past: 'what did I do last week', 'when was my last workout', 'show me what happened yesterday', 'have I missed anything recently'. Includes completed AND still-open (e.g. missed) items so the AI can tell the difference. Defaults to the last 7 days; pass `days` for a longer or shorter lookback.",
    input_schema: {
      type: 'object',
      properties: {
        days: { type: 'number', description: 'How many days back to look, ending at (not including) today. Defaults to 7.' },
      },
    },
  },
  async (input) => {
    const { days = 7 } = (input ?? {}) as { days?: number }
    const items = selectItemsArray(useSyncStore.getState())
    const end = startOfDay(new Date()) // exclusive — today itself is get_today's job, not this tool's
    const start = new Date(end.getTime() - Math.max(days, 0) * 86400_000)
    return items
      .filter((i) => {
        const d = anchorSortDate(i.anchor)
        return d && d >= start && d < end
      })
      .sort((a, b) => anchorSortDate(b.anchor)!.getTime() - anchorSortDate(a.anchor)!.getTime()) // most recent first
      .map(summarize)
  },
)

registerTool(
  {
    name: 'find_free_slots',
    description: 'Find open (unscheduled) time windows on a given day, between working hours.',
    input_schema: {
      type: 'object',
      properties: {
        date: { type: 'string', description: 'ISO8601 date, e.g. 2026-07-18' },
        minMinutes: { type: 'number', description: 'Minimum slot length in minutes to report' },
      },
      required: ['date'],
    },
  },
  async (input) => {
    const { date, minMinutes = 30 } = input as { date: string; minMinutes?: number }
    const target = new Date(date)
    const dayStart = new Date(target.getFullYear(), target.getMonth(), target.getDate(), 8, 0)
    const dayEnd = new Date(target.getFullYear(), target.getMonth(), target.getDate(), 20, 0)

    const items = selectItemsArray(useSyncStore.getState())
    const busy = items
      .filter((i) => i.anchor.type === 'timeBlock' && isSameDay(new Date(i.anchor.start), target))
      .map((i) => {
        const a = i.anchor as Extract<typeof i.anchor, { type: 'timeBlock' }>
        return { start: new Date(a.start), end: new Date(a.end) }
      })
      .sort((a, b) => a.start.getTime() - b.start.getTime())

    const freeSlots: { start: string; end: string }[] = []
    let cursor = dayStart
    for (const block of busy) {
      if (block.start.getTime() - cursor.getTime() >= minMinutes * 60_000) {
        freeSlots.push({ start: cursor.toISOString(), end: block.start.toISOString() })
      }
      if (block.end > cursor) cursor = block.end
    }
    if (dayEnd.getTime() - cursor.getTime() >= minMinutes * 60_000) {
      freeSlots.push({ start: cursor.toISOString(), end: dayEnd.toISOString() })
    }
    return { freeSlots }
  },
)

registerTool(
  {
    name: 'get_item',
    description: 'Look up a single item by id.',
    input_schema: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
  },
  async (input) => {
    const { id } = input as { id: string }
    const item = useSyncStore.getState().getItem(id)
    return item ? summarize(item) : { error: 'Item not found' }
  },
)
