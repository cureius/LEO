import { addItem, deleteItem, updateItem } from '@/sync/mutations'
import { useSyncStore } from '@/sync/store'
import type { DiffChange, PendingNewItem } from './types'
import type { DomainItem, EventItem, PlannedExercise, ReminderItem, TaskItem } from '@/domain/types'

export type ApplyDiffFailure = { change: DiffChange; message: string }

/**
 * Applies accepted DiffChanges through the SAME mutation functions any
 * manual edit uses — the AI never gets its own write path. This means
 * diff-applied changes get echo-suppression and realtime broadcast for
 * free, identical to any other edit; no separate plumbing needed here.
 *
 * Each change is caught individually rather than letting one failure abort
 * the whole batch — e.g. `deleteItem` throws synchronously (not just a
 * rejected promise it retries) for an EventKit-mirrored item, which
 * `propose_cancel` doesn't filter out. A user accepting "cancel my 3pm" where
 * that's a calendar-synced event would otherwise lose every change after it
 * in the same batch with no indication anything failed.
 */
export async function applyDiffChanges(changes: DiffChange[]): Promise<{ failures: ApplyDiffFailure[] }> {
  const failures: ApplyDiffFailure[] = []
  for (const change of changes) {
    try {
      switch (change.kind) {
        case 'add':
          if (change.pendingItem) await applyAdd(change.pendingItem)
          break
        case 'update':
          await applyUpdate(change)
          break
        case 'delete': {
          const item = useSyncStore.getState().getItem(change.itemID)
          if (item) await deleteItem(item)
          break
        }
      }
    } catch (err) {
      failures.push({ change, message: err instanceof Error ? err.message : String(err) })
    }
  }
  return { failures }
}

function buildNewItem(pending: PendingNewItem): DomainItem {
  const now = new Date()
  const base = {
    id: crypto.randomUUID(),
    title: pending.title,
    notes: pending.notes,
    createdAt: now,
    updatedAt: now,
    importance: 1,
    completion: { type: 'open' as const },
    tags: [],
  }
  const anchor = pending.start
    ? pending.end
      ? ({ type: 'timeBlock' as const, start: pending.start, end: pending.end })
      : ({ type: 'dueAt' as const, date: pending.start })
    : ({ type: 'untimed' as const })

  switch (pending.type) {
    case 'task':
      return { ...base, kind: 'task', anchor } satisfies TaskItem
    case 'event':
      return { ...base, kind: 'event', anchor, attendees: [] } satisfies EventItem
    case 'reminder':
      return { ...base, kind: 'reminder', anchor } satisfies ReminderItem
    case 'workout':
      return {
        ...base,
        kind: 'workout',
        anchor,
        // Use the structured exercises propose_workout_plan already computed
        // instead of dropping them — previously always empty regardless of
        // what the tool built, so an AI-generated workout landed with
        // nothing individually trackable.
        plannedExercises: (pending.exercises ?? []).map((e) => ({
          exerciseID: e.name,
          sets: e.sets,
          reps: e.reps,
          ...(e.weightKg !== undefined ? { weightKg: e.weightKg } : {}),
        })),
        estimatedKcal: pending.estimatedKcal ?? 0,
      }
    case 'meal':
      return { ...base, kind: 'meal', anchor, recipeID: 'ai-proposed', servings: 1, targetKcal: 0 }
  }
}

async function applyAdd(pending: PendingNewItem): Promise<void> {
  await addItem(buildNewItem(pending))
}

/**
 * `field: "anchor"` values come from propose_reschedule as
 * `"timeBlock:<start>–<end>"` or `"point:<start>"` — parse the same shape
 * that tool emits (proposeTools.ts). Any other `field` (currently just
 * "notes", from adjust_plan) is applied as a raw string onto that field.
 */
async function applyUpdate(change: DiffChange): Promise<void> {
  const item = useSyncStore.getState().getItem(change.itemID)
  if (!item) return

  if (change.field === 'anchor') {
    const timeBlockMatch = change.newValue.match(/^timeBlock:(.+)–(.+)$/)
    const pointMatch = change.newValue.match(/^point:(.+)$/)
    if (timeBlockMatch) {
      await updateItem({ ...item, anchor: { type: 'timeBlock', start: timeBlockMatch[1], end: timeBlockMatch[2] } })
    } else if (pointMatch) {
      await updateItem({ ...item, anchor: { type: 'point', date: pointMatch[1] } })
    }
    return
  }

  if (change.field === 'notes') {
    // `notes` is a shared field on every DomainItem kind (ItemBase) — no
    // per-kind cast needed.
    await updateItem({ ...item, notes: change.newValue })
    return
  }

  if (change.field === 'workoutDetail') {
    // Emitted by set_workout_exercises (fitnessTools.ts) — one JSON blob
    // covering both plannedExercises and the optional estimatedKcal in a
    // single change/updateItem call, not two separate DiffChanges. Two
    // changes sharing the same itemID would collide in DiffReview, which
    // keys/dedupes accept-toggle state by itemID.
    if (item.kind !== 'workout') return
    const detail = JSON.parse(change.newValue) as { exercises: PlannedExercise[]; estimatedKcal?: number }
    await updateItem({
      ...item,
      plannedExercises: detail.exercises,
      ...(detail.estimatedKcal !== undefined ? { estimatedKcal: detail.estimatedKcal } : {}),
    })
    return
  }
}
