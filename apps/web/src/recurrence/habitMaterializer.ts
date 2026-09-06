import { occurrences } from './expand'
import { timeOfDayHintHour } from '@/wire/habits'
import { anchorSortDate, type Anchor } from '@/wire/anchor'
import { addItem } from '@/sync/mutations'
import { selectItemsArray, useSyncStore } from '@/sync/store'
import type { Habit, HabitInstanceItem } from '@/domain/types'

/**
 * Port of LEO/Domain/Habits/HabitMaterializer.swift. Semantics confirmed
 * from source, not guessed:
 *
 *  - Rolling 14-day window from today (windowDays = 14 in the original).
 *  - Expansion anchor is ALWAYS `habit.createdAt`, never "last materialized
 *    date" — every run re-expands fresh from the habit's creation date
 *    through the current window; cheap because the window is bounded.
 *  - Dedup: for each occurrence day, skip if an instance for that day
 *    already exists and is non-open (never touch a resolved instance);
 *    also skip if ANY instance for that day exists at all, open or not
 *    (idempotent — never creates a second open instance for a day that
 *    already has one).
 *  - ADDITIVE ONLY — never deletes. If a habit's rule changes so a date is
 *    no longer an occurrence, an already-materialized open instance for it
 *    is orphaned, not cleaned up. This is inherited behavior, ported
 *    exactly as-is: a web client that "fixed" this would diverge from
 *    native, which would re-add what web considered removed — worse than
 *    matching the existing behavior.
 *  - Anchor time: habit.timeHint ?? morning -> hour (7/13/19/explicit),
 *    `.point` anchor, or `.timeBlock` if targetDuration is set.
 */
const WINDOW_DAYS = 14

function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

/** Exported for HabitsPage's tracker grid, which builds instances for past
 *  days on-demand the same way (see its "log a forgotten day" click handler)
 *  instead of only ever materializing forward from today. */
export function anchorDateFor(habit: Habit, date: Date): Anchor {
  const hint = habit.timeHint ?? { type: 'morning' as const }
  const hour = timeOfDayHintHour(hint)
  const minute = hint.type === 'specific' ? hint.minute : 0
  const anchorStart = new Date(date.getFullYear(), date.getMonth(), date.getDate(), hour, minute, 0)

  if (habit.targetDurationSeconds !== undefined) {
    const end = new Date(anchorStart.getTime() + habit.targetDurationSeconds * 1000)
    return { type: 'timeBlock', start: anchorStart.toISOString(), end: end.toISOString() }
  }
  return { type: 'point', date: anchorStart.toISOString() }
}

/** Generate instances for `habit` over the next WINDOW_DAYS days, writing
 *  any new ones through the normal item write path (sync/mutations.ts) so
 *  they sync to other devices identically to any other item. */
export async function materializeHabit(habit: Habit): Promise<void> {
  const today = startOfDay(new Date())
  const windowEnd = new Date(today.getTime() + WINDOW_DAYS * 86400_000)

  const dates = occurrences(
    { raw: habit.recurrenceRuleRaw, extensions: [] }, // extensions always [] — see wire/habits.ts doc comment
    habit.createdAt,
    today,
    windowEnd,
  )

  const existingByDay = new Map<number, HabitInstanceItem>()
  for (const item of selectItemsArray(useSyncStore.getState())) {
    if (item.kind !== 'habitInstance' || item.habitID !== habit.id) continue
    // anchorSortDate handles .point AND .timeBlock (the two shapes this
    // materializer itself produces, depending on targetDurationSeconds) —
    // falls back to createdAt only for the (here, unreachable) untimed case.
    const sortDate = anchorSortDate(item.anchor) ?? item.createdAt
    existingByDay.set(startOfDay(sortDate).getTime(), item)
  }

  const now = new Date()
  for (const date of dates) {
    const dayKey = startOfDay(date).getTime()
    const existing = existingByDay.get(dayKey)
    if (existing) continue // resolved OR merely-open-but-present — either way, idempotent skip

    const instance: HabitInstanceItem = {
      kind: 'habitInstance',
      id: crypto.randomUUID(),
      title: habit.name,
      createdAt: now,
      updatedAt: now,
      importance: 1,
      anchor: anchorDateFor(habit, date),
      completion: { type: 'open' },
      habitID: habit.id,
      targetDurationSeconds: habit.targetDurationSeconds,
    }
    await addItem(instance)
  }
}
