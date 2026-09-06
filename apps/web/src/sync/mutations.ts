import { toast } from 'sonner'
import { supabase } from '@/lib/supabaseClient'
import { encodeItemPayload, isExternallyManaged } from '@/wire/items'
import { encodeHabitPayload } from '@/wire/habits'
import { encodeMeasurementPayload } from '@/wire/fitness'
import { markItemPending, markHabitPending, sha256Hex } from './engine'
import { useSyncStore } from './store'
import { pushEventUpdateToGoogle, pushEventDeleteToGoogle } from '@/google/push'
import { anchorOnComplete } from '@/wire/anchor'
import type { DomainItem, Habit, HabitInstanceItem, Measurement } from '@/domain/types'

/**
 * Supabase's `PostgrestError` (thrown via `if (error) throw error` below) is
 * a plain object, not an `Error` instance — `String(plainObject)` renders as
 * the useless literal "[object Object]", which shipped in a toast before
 * this was caught live. Extract `.message` when present instead of
 * String()-coercing whatever shape was thrown.
 */
export function errorMessage(err: unknown): string {
  if (err instanceof Error) return err.message
  if (typeof err === 'object' && err !== null) {
    if ('message' in err && typeof err.message === 'string') return err.message
    // A plain object with no .message would otherwise fall through to
    // String() and render as the literal, useless "[object Object]" — a
    // real toast shipped that before this was caught live. JSON.stringify
    // at least shows the actual shape.
    try {
      return JSON.stringify(err)
    } catch {
      return 'Unknown error'
    }
  }
  return String(err)
}

/**
 * All write paths funnel through here so echo-suppression (markItemPending)
 * and rollback-on-failure are never duplicated per call site — matches the
 * repo-wide "no empty catch blocks, no silent failure" rule (plans/conventions.md)
 * and the plan's §4 optimistic-write design.
 */
async function pushItem(item: DomainItem): Promise<void> {
  if (isExternallyManaged(item)) {
    // Structural guarantee, not just a UI-level disabled button: even a
    // future caller that skips the UI can't push an EventKit mirror and
    // duplicate it back onto its origin device — the exact bug fixed in the
    // native Swift app this session.
    throw new Error('Cannot write an item synced from Calendar/Reminders — it is read-only.')
  }

  const { data: sessionData } = await supabase.auth.getSession()
  const userId = sessionData.session?.user.id
  if (!userId) throw new Error('Not signed in')

  const { kind, json } = encodeItemPayload(item)
  const row = {
    id: item.id,
    user_id: userId,
    kind,
    title: item.title,
    data: json,
    updated_at: item.updatedAt.toISOString(),
    deleted_at: null,
  }

  // Mark pending BEFORE the network call — the realtime echo can arrive
  // before `upsert` even resolves locally, and it must find this entry.
  markItemPending(item.id, item.updatedAt.getTime())
  const { error } = await supabase.from('items').upsert(row)
  if (error) throw error
}

/** Create a new item. Optimistic: visible immediately, rolled back on failure. */
export async function addItem(item: DomainItem): Promise<void> {
  const store = useSyncStore.getState()
  store.upsertItem(item)
  try {
    await pushItem(item)
  } catch (err) {
    store.removeItem(item.id)
    toast.error(`Couldn't create "${item.title}"`, { description: errorMessage(err), action: { label: 'Retry', onClick: () => void addItem(item) } })
  }
}

/** Edit an existing item. `updatedAt` is always refreshed to now — mirrors
 *  the native fix this session where several completion/edit paths forgot
 *  to bump it, silently making the edit invisible to sync's push filter.
 *
 *  `skipGooglePush` exists for exactly one caller: google/sync.ts's PULL
 *  path also funnels through this function (so it gets the same optimistic/
 *  rollback/toast behavior as every other write), but an item it just wrote
 *  FROM a Google event must never immediately push right back TO Google —
 *  that's a pointless round trip at best and a redundant-write ping-pong at
 *  worst. Every real UI edit path (ItemDetailPanel, DebugPage, chat tools,
 *  …) omits this and gets the push as normal. */
export async function updateItem(item: DomainItem, options: { skipGooglePush?: boolean } = {}): Promise<void> {
  const store = useSyncStore.getState()
  const previous = store.getItem(item.id)
  const updated: DomainItem = { ...item, updatedAt: new Date() }
  store.upsertItem(updated)
  try {
    await pushItem(updated)
    if (!options.skipGooglePush && updated.kind === 'event') {
      // Failures here are reported but don't roll back the LOCAL save —
      // the edit already succeeded in LEO; Google being unreachable is a
      // separate, secondary problem, not a reason to discard the user's edit.
      pushEventUpdateToGoogle(updated).catch((err) => {
        toast.error("Saved in LEO, but couldn't sync to Google Calendar", { description: errorMessage(err) })
      })
    }
  } catch (err) {
    if (previous) store.upsertItem(previous)
    else store.removeItem(item.id)
    toast.error(`Couldn't save "${item.title}"`, { description: errorMessage(err), action: { label: 'Retry', onClick: () => void updateItem(item, options) } })
  }
}

/** Toggle open <-> completed. A thin wrapper over updateItem so every call
 *  site gets the same optimistic/rollback/toast behavior for free. */
export async function toggleComplete(item: DomainItem): Promise<void> {
  const nowOpen = item.completion.type !== 'open'
  const now = new Date()
  await updateItem({
    ...item,
    // Un-completing deliberately leaves the anchor exactly as it is rather
    // than trying to revert an untimed->dueAt pin from anchorOnComplete —
    // there's no reliable way to tell "this dueAt was auto-assigned by
    // completing it" from "the user deliberately timed this item" after
    // the fact, and guessing wrong would silently un-schedule a real edit.
    anchor: nowOpen ? item.anchor : anchorOnComplete(item.anchor, now),
    completion: nowOpen ? { type: 'open' } : { type: 'completed', date: now.toISOString() },
  })
}

/** Soft-delete — sets deleted_at, which the decode path (engine.ts
 *  applyItemRow) already treats as "remove from store" for any device that
 *  pulls or receives this row, matching the native tombstone pattern.
 *  `skipGooglePush` — same reasoning as updateItem's: google/sync.ts calls
 *  this to mirror a Google-side cancellation into LEO, which must not turn
 *  around and re-issue a delete back to the Google event that was already
 *  the SOURCE of this delete. */
export async function deleteItem(item: DomainItem, options: { skipGooglePush?: boolean } = {}): Promise<void> {
  if (isExternallyManaged(item)) {
    throw new Error('Cannot delete an item synced from Calendar/Reminders here.')
  }
  const store = useSyncStore.getState()
  store.removeItem(item.id)
  try {
    const { data: sessionData } = await supabase.auth.getSession()
    const userId = sessionData.session?.user.id
    if (!userId) throw new Error('Not signed in')
    const { error } = await supabase
      .from('items')
      .update({ deleted_at: new Date().toISOString() })
      .eq('id', item.id)
      .eq('user_id', userId)
    if (error) throw error
    if (!options.skipGooglePush && item.kind === 'event') {
      pushEventDeleteToGoogle(item.id).catch((err) => {
        toast.error("Deleted in LEO, but couldn't sync the deletion to Google Calendar", { description: errorMessage(err) })
      })
    }
  } catch (err) {
    store.upsertItem(item)
    toast.error(`Couldn't delete "${item.title}"`, { description: errorMessage(err), action: { label: 'Retry', onClick: () => void deleteItem(item, options) } })
  }
}

// ---------------------------------------------------------------------------
// Habits — hash-based echo suppression, not updatedAt-based, because
// SnapshotHabit carries no updatedAt field in its payload (confirmed absent
// from source) — see wire/habits.ts and sync/engine.ts's applyHabitRow.
// ---------------------------------------------------------------------------

async function pushHabit(habit: Habit): Promise<void> {
  const { data: sessionData } = await supabase.auth.getSession()
  const userId = sessionData.session?.user.id
  if (!userId) throw new Error('Not signed in')

  const json = encodeHabitPayload(habit)
  const hash = await sha256Hex(json)
  markHabitPending(habit.id, hash) // before the network call, same reasoning as pushItem

  const { error } = await supabase
    .from('habits')
    .upsert({ id: habit.id, user_id: userId, name: habit.name, data: json, deleted_at: null })
  if (error) throw error
}

export async function addHabit(habit: Habit): Promise<void> {
  const store = useSyncStore.getState()
  store.upsertHabit(habit)
  try {
    await pushHabit(habit)
  } catch (err) {
    store.removeHabit(habit.id)
    toast.error(`Couldn't create "${habit.name}"`, { description: errorMessage(err), action: { label: 'Retry', onClick: () => void addHabit(habit) } })
  }
}

export async function setHabitArchived(habit: Habit, isArchived: boolean): Promise<void> {
  const store = useSyncStore.getState()
  const previous = habit
  const updated: Habit = { ...habit, isArchived }
  store.upsertHabit(updated)
  try {
    await pushHabit(updated)
  } catch (err) {
    store.upsertHabit(previous)
    toast.error(`Couldn't update "${habit.name}"`, { description: errorMessage(err), action: { label: 'Retry', onClick: () => void setHabitArchived(habit, isArchived) } })
  }
}

/** Soft-delete — same tombstone pattern as deleteItem, plus its logged
 *  instances: matches HabitRepository.delete(id:)'s doc comment on the
 *  native side ("Permanently deletes a habit and all of its logged
 *  instances") rather than leaving orphaned habitInstance items with no
 *  parent habit behind. Callers pass the instances explicitly (rather than
 *  this function querying for them) since the store already has them
 *  in-memory wherever a habit's own instances are being displayed. */
export async function deleteHabit(habit: Habit, instances: HabitInstanceItem[]): Promise<void> {
  const store = useSyncStore.getState()
  store.removeHabit(habit.id)
  for (const instance of instances) store.removeItem(instance.id)
  try {
    const { data: sessionData } = await supabase.auth.getSession()
    const userId = sessionData.session?.user.id
    if (!userId) throw new Error('Not signed in')
    const now = new Date().toISOString()
    const { error: habitError } = await supabase.from('habits').update({ deleted_at: now }).eq('id', habit.id).eq('user_id', userId)
    if (habitError) throw habitError
    if (instances.length > 0) {
      const { error: itemsError } = await supabase
        .from('items')
        .update({ deleted_at: now })
        .in('id', instances.map((i) => i.id))
        .eq('user_id', userId)
      if (itemsError) throw itemsError
    }
  } catch (err) {
    store.upsertHabit(habit)
    for (const instance of instances) store.upsertItem(instance)
    toast.error(`Couldn't delete "${habit.name}"`, {
      description: errorMessage(err),
      action: { label: 'Retry', onClick: () => void deleteHabit(habit, instances) },
    })
  }
}

// ---------------------------------------------------------------------------
// Measurements — no echo-suppression map like items/habits above, since
// nothing in the web app currently writes these except the debug page
// (DebugPage.tsx); a same-tab realtime echo just re-applies the identical
// value via upsertMeasurement, a harmless no-op.
// ---------------------------------------------------------------------------

async function pushMeasurement(measurement: Measurement): Promise<void> {
  const { data: sessionData } = await supabase.auth.getSession()
  const userId = sessionData.session?.user.id
  if (!userId) throw new Error('Not signed in')
  const json = encodeMeasurementPayload(measurement)
  const { error } = await supabase.from('measurements').upsert({ id: measurement.id, user_id: userId, data: json, deleted_at: null })
  if (error) throw error
}

/** Upsert — covers both create and edit, same as addHabit does for habits. */
export async function saveMeasurement(measurement: Measurement): Promise<void> {
  const store = useSyncStore.getState()
  const previous = store.measurements.get(measurement.id)
  store.upsertMeasurement(measurement)
  try {
    await pushMeasurement(measurement)
  } catch (err) {
    if (previous) store.upsertMeasurement(previous)
    else store.removeMeasurement(measurement.id)
    toast.error("Couldn't save measurement", { description: errorMessage(err), action: { label: 'Retry', onClick: () => void saveMeasurement(measurement) } })
  }
}

export async function deleteMeasurement(measurement: Measurement): Promise<void> {
  const store = useSyncStore.getState()
  store.removeMeasurement(measurement.id)
  try {
    const { data: sessionData } = await supabase.auth.getSession()
    const userId = sessionData.session?.user.id
    if (!userId) throw new Error('Not signed in')
    const { error } = await supabase
      .from('measurements')
      .update({ deleted_at: new Date().toISOString() })
      .eq('id', measurement.id)
      .eq('user_id', userId)
    if (error) throw error
  } catch (err) {
    store.upsertMeasurement(measurement)
    toast.error("Couldn't delete measurement", {
      description: errorMessage(err),
      action: { label: 'Retry', onClick: () => void deleteMeasurement(measurement) },
    })
  }
}
