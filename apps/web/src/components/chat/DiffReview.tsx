import { useState } from 'react'
import { Sparkles, Plus, Pencil, Trash2 } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { applyDiffChanges } from '@/ai/diff/applyDiff'
import type { DiffPayload, DiffChange } from '@/ai/diff/types'

const KIND_ICON = { add: Plus, update: Pencil, delete: Trash2 } as const

/**
 * Port of DiffReviewSheet.swift's contract: rationale header, per-change
 * accept/reject toggle (all pre-accepted by default), one "Apply N changes"
 * button that commits only the accepted ones. This is the ONLY place a
 * proposed AI change can ever reach the store — applyDiffChanges routes
 * through the same mutations any manual edit uses.
 */
export function DiffReview({ diff, onResolved }: { diff: DiffPayload; onResolved: () => void }) {
  const [accepted, setAccepted] = useState<Set<string>>(new Set(diff.changes.map((c) => c.itemID)))
  const [applying, setApplying] = useState(false)

  function toggle(itemID: string) {
    setAccepted((prev) => {
      const next = new Set(prev)
      if (next.has(itemID)) next.delete(itemID)
      else next.add(itemID)
      return next
    })
  }

  async function handleApply() {
    setApplying(true)
    try {
      const acceptedChanges = diff.changes.filter((c) => accepted.has(c.itemID))
      const { failures } = await applyDiffChanges(acceptedChanges)
      if (failures.length > 0) {
        toast.error(`${failures.length} of ${acceptedChanges.length} change${acceptedChanges.length === 1 ? '' : 's'} couldn't be applied`, {
          description: failures.map((f) => f.message).join('; '),
        })
      }
    } finally {
      // Always runs, even if applyDiffChanges itself throws unexpectedly —
      // without this, any error here left the button stuck on "Applying…"
      // forever with the panel never closing (caught live: deleteItem throws
      // synchronously for an EventKit-mirrored item, which propose_cancel
      // doesn't filter out, and that exception had nothing catching it here).
      setApplying(false)
      onResolved()
    }
  }

  const acceptedCount = accepted.size

  return (
    <div className="mt-2 rounded-leo-md border border-divider bg-surface-elevated p-3">
      <div className="mb-2 flex items-center gap-1.5 text-xs font-medium text-accent">
        <Sparkles className="h-3.5 w-3.5" aria-hidden="true" />
        LEO suggests
      </div>
      <p className="mb-3 text-sm text-text-primary">{diff.rationale}</p>

      <ul className="mb-3 flex flex-col gap-1.5">
        {diff.changes.map((change) => (
          <DiffChangeRow key={change.itemID} change={change} isAccepted={accepted.has(change.itemID)} onToggle={() => toggle(change.itemID)} />
        ))}
      </ul>

      <div className="flex gap-2">
        <Button variant="secondary" size="sm" onClick={onResolved} disabled={applying}>
          Dismiss
        </Button>
        <Button size="sm" onClick={handleApply} disabled={applying || acceptedCount === 0}>
          {applying ? 'Applying…' : `Apply ${acceptedCount} change${acceptedCount === 1 ? '' : 's'}`}
        </Button>
      </div>
    </div>
  )
}

/** `workoutDetail` (set_workout_exercises) carries a JSON blob in `newValue`
 *  — render it as a readable exercise summary instead of raw JSON text. */
function summarizeChange(change: DiffChange): string {
  if (change.kind === 'add') return change.pendingItem?.title ?? change.newValue
  if (change.field === 'workoutDetail') {
    try {
      const detail = JSON.parse(change.newValue) as { exercises: { exerciseID: string; sets: number; reps: number }[] }
      return detail.exercises.map((e) => `${e.exerciseID} ${e.sets}×${e.reps}`).join(', ')
    } catch {
      return 'Update workout exercises'
    }
  }
  return change.newValue || `Update ${change.field}`
}

function DiffChangeRow({ change, isAccepted, onToggle }: { change: DiffChange; isAccepted: boolean; onToggle: () => void }) {
  const Icon = KIND_ICON[change.kind]
  const title = summarizeChange(change)

  return (
    <li className={`flex items-center gap-2 rounded-leo-sm border border-divider bg-surface px-2 py-1.5 ${isAccepted ? '' : 'opacity-45'}`}>
      <Icon className="h-3.5 w-3.5 shrink-0 text-text-secondary" aria-hidden="true" />
      <span className="flex-1 text-sm text-text-primary">{title}</span>
      <input type="checkbox" checked={isAccepted} onChange={onToggle} aria-label={`Include "${title}" in this change`} />
    </li>
  )
}
