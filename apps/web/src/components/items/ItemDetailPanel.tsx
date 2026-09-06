import { useState } from 'react'
import { Link } from 'react-router-dom'
import * as Dialog from '@radix-ui/react-dialog'
import { X, Trash2, Copy, CheckCircle2, Circle, RefreshCw, Maximize2, Minimize2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { DateTimePicker } from '@/components/ui/DateTimePicker'
import { MarkdownField } from '@/components/markdown/MarkdownField'
import { TagChip } from '@/components/ui/TagChip'
import { RESPONSIVE_DIALOG_OVERLAY } from '@/components/ui/responsiveDialog'
import { SIDE_PANEL_CONTENT, useSidePanelEntrance } from '@/components/ui/sidePanel'
import { cn } from '@/lib/utils'
import { TagEditor } from './TagEditor'
import { addItem, deleteItem, updateItem } from '@/sync/mutations'
import { useSyncStore } from '@/sync/store'
import { isExternallyManaged } from '@/wire/items'
import { kindLabel } from '@/domain/itemDisplay'
import type { Anchor, Completion } from '@/wire/anchor'
import type { DomainItem, Tag } from '@/domain/types'

type AnchorMode = 'untimed' | 'dueAt' | 'timeBlock'

// Overrides SIDE_PANEL_CONTENT's sm:w-[420px] lg:w-[480px] — cn()'s
// tailwind-merge resolves the conflict in favor of whichever width class
// comes later, so this only ever affects THIS panel, not Jira's issue
// detail (the other SIDE_PANEL_CONTENT caller), which never adds it.
const EXPANDED_WIDTH = 'sm:w-[720px] lg:w-[880px]'
const EXPANDED_STORAGE_KEY = 'leo:item-detail-expanded'

function loadExpandedPref(): boolean {
  return localStorage.getItem(EXPANDED_STORAGE_KEY) === '1'
}

function saveExpandedPref(expanded: boolean): void {
  localStorage.setItem(EXPANDED_STORAGE_KEY, expanded ? '1' : '0')
}

function formatDateTime(d: Date): string {
  return d.toLocaleString(undefined, { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' })
}

function statusLine(completion: Completion): string | undefined {
  if (completion.type === 'completed') return `Completed ${formatDateTime(new Date(completion.date))}`
  if (completion.type === 'skipped') return `Skipped ${formatDateTime(new Date(completion.date))}${completion.reason ? ` — ${completion.reason}` : ''}`
  if (completion.type === 'dismissed') return 'Dismissed'
  return undefined
}

/**
 * Click-to-open editor — every native platform (iOS, Mac) opens a detail
 * sheet/inspector when an item row is tapped. A right-docked, full-height
 * panel rather than a centered dialog: a task with notes + tags + kind
 * fields + a markdown editor needed more room than a ~400px floating box
 * gave it, and a panel reads as "inspecting this item alongside the list"
 * rather than "the list is blocked until you deal with this."
 */
export function ItemDetailPanel({ item, onClose }: { item: DomainItem; onClose: () => void }) {
  const readOnly = isExternallyManaged(item)
  const googleLink = useSyncStore((s) => s.googleLinks.get(item.id))
  const [title, setTitle] = useState(item.title)
  const [notes, setNotes] = useState(item.notes ?? '')
  const [importance, setImportance] = useState(item.importance)
  const [completion, setCompletion] = useState<Completion>(item.completion)
  const [anchorMode, setAnchorMode] = useState<AnchorMode>(item.anchor.type === 'timeBlock' ? 'timeBlock' : item.anchor.type === 'untimed' ? 'untimed' : 'dueAt')
  const [dueAt, setDueAt] = useState(item.anchor.type === 'dueAt' || item.anchor.type === 'point' ? item.anchor.date : '')
  const [blockStart, setBlockStart] = useState(item.anchor.type === 'timeBlock' ? item.anchor.start : '')
  const [blockEnd, setBlockEnd] = useState(item.anchor.type === 'timeBlock' ? item.anchor.end : '')
  const [tags, setTags] = useState<Tag[]>('tags' in item ? item.tags : [])

  // Kind-specific editable fields — seeded from whichever kind `item` is;
  // only the matching block below ever reads/writes each one back.
  const [deadline, setDeadline] = useState(item.kind === 'task' ? (item.deadline ? item.deadline.toISOString() : '') : '')
  const [estimatedDurationMin, setEstimatedDurationMin] = useState(
    item.kind === 'task' && item.estimatedDurationSeconds ? String(Math.round(item.estimatedDurationSeconds / 60)) : '',
  )
  const [location, setLocation] = useState(item.kind === 'event' ? (item.location ?? '') : '')
  const [leadTimeMin, setLeadTimeMin] = useState(item.kind === 'reminder' && item.leadTime ? String(Math.round(item.leadTime / 60)) : '')

  const [saving, setSaving] = useState(false)
  const [duplicating, setDuplicating] = useState(false)
  const [dirty, setDirty] = useState(false)
  // Persisted across tasks (not per-item) — expanding once to work on a
  // long note means the next task opened also gets the room, rather than
  // re-toggling every time.
  const [expanded, setExpanded] = useState(loadExpandedPref)
  const done = completion.type !== 'open'

  function toggleExpanded() {
    setExpanded((prev) => {
      const next = !prev
      saveExpandedPref(next)
      return next
    })
  }

  /** Wraps a field setter so any edit marks the panel dirty — closing the
   *  panel (X, overlay click, Escape) auto-saves when dirty instead of
   *  silently discarding the edit, the same as clicking Save explicitly. */
  function edited<T>(setter: (value: T) => void) {
    return (value: T) => {
      setter(value)
      setDirty(true)
    }
  }

  const { contentClass, overlayClass } = useSidePanelEntrance()

  /** Independent of Save — matches how completion toggling works everywhere
   *  else in the app (ItemRow, DayTimeline): immediate, not batched into a
   *  bigger edit. Still tracked in local state (not just fired-and-forgotten)
   *  so a subsequent Save click includes it instead of reverting to
   *  whatever `item.completion` was when the panel first opened. */
  async function handleToggleDone() {
    const next: Completion = done ? { type: 'open' } : { type: 'completed', date: new Date().toISOString() }
    setCompletion(next)
    await updateItem({ ...item, completion: next })
  }

  /** Assembles a DomainItem from the current form state — shared by Save
   *  (persists it as this item) and Duplicate (persists it as a new one),
   *  so duplicating reflects whatever's actually on screen right now,
   *  including edits not yet saved. */
  function buildEditedItem(): DomainItem {
    const anchor: Anchor =
      anchorMode === 'untimed'
        ? { type: 'untimed' }
        : anchorMode === 'dueAt' && dueAt
          ? { type: 'dueAt', date: dueAt }
          : anchorMode === 'timeBlock' && blockStart && blockEnd
            ? { type: 'timeBlock', start: blockStart, end: blockEnd }
            : item.anchor // fall back rather than write an incomplete anchor

    let updated: DomainItem = { ...item, title: title.trim() || item.title, notes: notes || undefined, importance, anchor, completion }
    if ('tags' in updated) updated = { ...updated, tags }
    if (updated.kind === 'task') {
      updated = {
        ...updated,
        deadline: deadline ? new Date(deadline) : undefined,
        estimatedDurationSeconds: estimatedDurationMin ? Number(estimatedDurationMin) * 60 : undefined,
      }
    }
    if (updated.kind === 'event') {
      updated = { ...updated, location: location || undefined }
    }
    if (updated.kind === 'reminder') {
      updated = { ...updated, leadTime: leadTimeMin ? Number(leadTimeMin) * 60 : undefined }
    }
    return updated
  }

  async function persistIfDirty() {
    if (!dirty || readOnly) return
    await updateItem(buildEditedItem())
    setDirty(false)
  }

  async function handleSave() {
    setSaving(true)
    await persistIfDirty()
    setSaving(false)
    onClose()
  }

  /** Closing the panel any other way (X button, overlay click, Escape —
   *  all funnel through Dialog.Root's onOpenChange) still auto-saves a
   *  dirty edit first, so "close" never means "discard." */
  async function handleClose() {
    setSaving(true)
    await persistIfDirty()
    setSaving(false)
    onClose()
  }

  async function handleDelete() {
    await deleteItem(item)
    onClose()
  }

  async function handleDuplicate() {
    setDuplicating(true)
    const base = buildEditedItem()
    const now = new Date()
    await addItem({ ...base, id: crypto.randomUUID(), title: `Copy of ${base.title}`, createdAt: now, updatedAt: now, completion: { type: 'open' } })
    setDuplicating(false)
    onClose()
  }

  return (
    <Dialog.Root open onOpenChange={(open) => !open && void handleClose()}>
      <Dialog.Portal>
        <Dialog.Overlay className={cn(RESPONSIVE_DIALOG_OVERLAY, overlayClass)} />
        <Dialog.Content className={cn(SIDE_PANEL_CONTENT, 'transition-[width] duration-200 ease-out', expanded && EXPANDED_WIDTH, contentClass)}>
          <div className="flex shrink-0 items-center justify-between border-b border-divider p-4">
            <div className="flex items-center gap-2">
              <Dialog.Title className="text-sm font-medium text-text-secondary">{kindLabel(item.kind)}</Dialog.Title>
              {done && <span className="rounded-leo-pill bg-success/15 px-2 py-0.5 text-xs font-medium text-success">Done</span>}
            </div>
            <div className="flex items-center gap-1">
              <button
                type="button"
                onClick={toggleExpanded}
                aria-label={expanded ? 'Collapse panel' : 'Expand panel for more room to write notes'}
                title={expanded ? 'Collapse' : 'Expand'}
                className="hidden rounded-leo-sm p-1 text-text-secondary hover:bg-surface-elevated sm:inline-flex"
              >
                {expanded ? <Minimize2 className="h-4 w-4" /> : <Maximize2 className="h-4 w-4" />}
              </button>
              {!readOnly && item.kind !== 'habitInstance' && (
                <button
                  type="button"
                  onClick={() => void handleDuplicate()}
                  disabled={duplicating}
                  aria-label={`Duplicate "${item.title}"`}
                  title="Duplicate"
                  className="rounded-leo-sm p-1 text-text-secondary hover:bg-surface-elevated disabled:opacity-50"
                >
                  <Copy className="h-4 w-4" />
                </button>
              )}
              <Dialog.Close asChild>
                <button aria-label="Close" className="rounded-leo-sm p-1 text-text-secondary hover:bg-surface-elevated">
                  <X className="h-4 w-4" />
                </button>
              </Dialog.Close>
            </div>
          </div>

          <div className="min-h-0 flex-1 overflow-y-auto p-4">
            {readOnly ? (
              <>
                <p className="mb-1 text-lg font-semibold text-text-primary">{item.title}</p>
                <p className="text-sm text-text-secondary">
                  Synced from Calendar/Reminders — this item is read-only here. Edit it in Calendar or Reminders on your
                  phone/Mac instead.
                </p>
              </>
            ) : (
              <div className="flex flex-col gap-4">
                <div className="flex flex-col gap-1">
                  <button
                    type="button"
                    onClick={() => void handleToggleDone()}
                    className={`flex items-center gap-2 self-start rounded-leo-pill border px-3 py-1.5 text-sm font-medium transition-colors ${
                      done ? 'border-success/30 bg-success/10 text-success' : 'border-divider text-text-secondary hover:bg-surface-elevated'
                    }`}
                  >
                    {done ? <CheckCircle2 className="h-4 w-4" /> : <Circle className="h-4 w-4" />}
                    {done ? 'Completed' : 'Mark as done'}
                  </button>
                  {statusLine(completion) && <span className="text-xs text-text-secondary">{statusLine(completion)}</span>}
                  {googleLink && (
                    <span className="flex items-center gap-1 text-xs text-text-secondary">
                      <RefreshCw className="h-3 w-3" aria-hidden="true" />
                      Synced with Google Calendar{googleLink.googleRecurringEventId ? ' · Repeats' : ''}
                    </span>
                  )}
                </div>

                <div className="flex flex-col gap-1.5">
                  <Label htmlFor="detail-title">Title</Label>
                  <Input id="detail-title" value={title} onChange={(e) => edited(setTitle)(e.target.value)} />
                </div>

                <div className="flex flex-col gap-1.5">
                  <span className="text-sm font-medium text-text-primary">When</span>
                  <div className="flex gap-2">
                    {(['untimed', 'dueAt', 'timeBlock'] as const).map((mode) => (
                      <Button key={mode} type="button" size="sm" variant={anchorMode === mode ? 'default' : 'secondary'} onClick={() => edited(setAnchorMode)(mode)}>
                        {mode === 'untimed' ? 'No time' : mode === 'dueAt' ? 'Due at' : 'Time block'}
                      </Button>
                    ))}
                  </div>
                  {anchorMode === 'dueAt' && <DateTimePicker value={dueAt} onChange={edited(setDueAt)} />}
                  {anchorMode === 'timeBlock' && (
                    // Stacked, not side-by-side — a side-by-side End picker's
                    // trigger sat close to the panel's edge, and its
                    // Popover routinely had nowhere to open without
                    // overflowing on narrower viewports.
                    <div className="flex flex-col gap-2">
                      <DateTimePicker value={blockStart} onChange={edited(setBlockStart)} placeholder="Start" />
                      <DateTimePicker value={blockEnd} onChange={edited(setBlockEnd)} placeholder="End" />
                    </div>
                  )}
                </div>

                <div className="flex flex-col gap-1.5">
                  <span className="text-sm font-medium text-text-primary">Importance</span>
                  <div className="flex gap-2">
                    {(['Normal', 'High', 'Urgent'] as const).map((label, i) => {
                      const value = i + 1
                      return (
                        <Button key={label} type="button" size="sm" variant={importance === value ? 'default' : 'secondary'} onClick={() => edited(setImportance)(value)}>
                          {label}
                        </Button>
                      )
                    })}
                  </div>
                </div>

                {item.kind === 'task' && (
                  <div className="grid grid-cols-2 gap-3">
                    <div className="flex flex-col gap-1.5">
                      <Label htmlFor="detail-deadline">Deadline</Label>
                      <DateTimePicker id="detail-deadline" value={deadline} onChange={edited(setDeadline)} placeholder="None" />
                    </div>
                    <div className="flex flex-col gap-1.5">
                      <Label htmlFor="detail-duration">Est. duration (min)</Label>
                      <Input
                        id="detail-duration"
                        type="number"
                        min="0"
                        value={estimatedDurationMin}
                        onChange={(e) => edited(setEstimatedDurationMin)(e.target.value)}
                      />
                    </div>
                  </div>
                )}

                {item.kind === 'event' && (
                  <div className="flex flex-col gap-3">
                    <div className="flex flex-col gap-1.5">
                      <Label htmlFor="detail-location">Location</Label>
                      <Input id="detail-location" value={location} onChange={(e) => edited(setLocation)(e.target.value)} placeholder="Add a location" />
                    </div>
                    {item.attendees.length > 0 && (
                      <div className="flex flex-col gap-1">
                        <span className="text-xs font-medium text-text-secondary">Attendees</span>
                        <p className="text-sm text-text-primary">{item.attendees.join(', ')}</p>
                      </div>
                    )}
                  </div>
                )}

                {item.kind === 'reminder' && (
                  <div className="flex flex-col gap-1.5">
                    <Label htmlFor="detail-leadtime">Remind me before (min)</Label>
                    <Input id="detail-leadtime" type="number" min="0" value={leadTimeMin} onChange={(e) => edited(setLeadTimeMin)(e.target.value)} />
                  </div>
                )}

                {item.kind === 'alarm' && (
                  <div className="flex flex-col gap-1 rounded-leo-sm bg-surface-elevated p-2.5 text-sm">
                    <span className="text-text-secondary">
                      Sound: <span className="text-text-primary">{item.soundProfileRaw.replace(/_/g, ' ')}</span>
                    </span>
                    <span className="text-text-secondary">
                      Escalates: <span className="text-text-primary">{item.escalates ? 'Yes' : 'No'}</span>
                    </span>
                  </div>
                )}

                {item.kind === 'workout' && (
                  <div className="rounded-leo-sm bg-surface-elevated p-2.5 text-sm">
                    <p className="text-text-primary">
                      ~{item.estimatedKcal} kcal estimated{item.actualKcal !== undefined ? ` · ${item.actualKcal} kcal actual` : ''}
                    </p>
                    {item.plannedExercises.length > 0 && (
                      <p className="mt-1 text-xs text-text-secondary">
                        {item.plannedExercises.length} exercise{item.plannedExercises.length === 1 ? '' : 's'} planned — edit in Fitness
                      </p>
                    )}
                  </div>
                )}

                {item.kind === 'meal' && (
                  <div className="rounded-leo-sm bg-surface-elevated p-2.5 text-sm text-text-primary">
                    {item.servings} serving{item.servings === 1 ? '' : 's'} · {item.actualKcal ?? item.targetKcal} / {item.targetKcal} kcal
                  </div>
                )}

                {item.kind === 'habitInstance' && (
                  <p className="text-xs text-text-secondary">Part of a habit — edit the habit itself from the Habits page.</p>
                )}

                <MarkdownField id="detail-notes" label="Notes" value={notes} onChange={edited(setNotes)} rows={expanded ? 20 : 6} />

                {'tags' in item && (
                  <>
                    <TagEditor tags={tags} onChange={edited(setTags)} />
                    {tags.length > 0 && (
                      <div className="flex flex-col gap-1.5">
                        <span className="text-xs font-medium text-text-secondary">Open project</span>
                        <div className="flex flex-wrap gap-1.5">
                          {tags.map((t) => (
                            <Link key={t.id} to={`/projects/${encodeURIComponent(t.name)}`} className="hover:opacity-80">
                              <TagChip tag={t} />
                            </Link>
                          ))}
                        </div>
                      </div>
                    )}
                  </>
                )}

                <p className="text-xs text-text-secondary">
                  Created {formatDateTime(item.createdAt)}
                  {item.updatedAt.getTime() !== item.createdAt.getTime() && ` · Updated ${formatDateTime(item.updatedAt)}`}
                </p>
              </div>
            )}
          </div>

          {!readOnly && (
            <div className="flex shrink-0 items-center justify-between border-t border-divider p-4">
              <Button type="button" variant="ghost" onClick={handleDelete} className="text-danger hover:text-danger">
                <Trash2 className="mr-1.5 h-4 w-4" /> Delete
              </Button>
              <Button type="button" onClick={handleSave} disabled={saving}>
                {saving ? 'Saving…' : 'Save'}
              </Button>
            </div>
          )}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  )
}
