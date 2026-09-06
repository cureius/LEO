import { useMemo, useRef, useState, type DragEvent } from 'react'
import { useShallow } from 'zustand/react/shallow'
import { QuickAddSection } from '@/components/items/QuickAddSection'
import { ItemRow } from '@/components/items/ItemRow'
import { DayTimeline } from '@/components/items/DayTimeline'
import { DateNavigator } from '@/components/items/DateNavigator'
import { selectItemsArray, useSyncStore } from '@/sync/store'
import { updateItem } from '@/sync/mutations'
import { anchorEndDate, anchorIsUntimed, anchorSortDate, anchorSortPriority } from '@/wire/anchor'
import { isExternallyManaged } from '@/wire/items'
import { cn } from '@/lib/utils'
import type { DomainItem } from '@/domain/types'

type ScheduledView = 'list' | 'timeline'
type BacklogSort = 'manual' | 'project'

function isSameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}
function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}

/**
 * Port of TodayViewModel.swift's actual behavior: the view merges the
 * selected day's scheduled items with the entire untimed backlog, so you
 * see everything actionable in one place. The backlog itself has no date
 * (that's what "untimed" means) so the SAME global list shows regardless
 * of which day is selected — it's not day-scoped, just always-visible
 * alongside whichever day you're looking at, so you can schedule into (or
 * unschedule back out of) any day without first flipping to today. The
 * original web build wrongly split these into two disjoint pages (Today =
 * timed-only, Inbox = untimed-only), which is why nothing carried over
 * between them.
 */
export function TodayPage() {
  const items = useSyncStore(useShallow(selectItemsArray))
  const initialLoadComplete = useSyncStore((s) => s.initialLoadComplete)
  const [selectedDate, setSelectedDate] = useState(() => startOfDay(new Date()))
  const [scheduledView, setScheduledView] = useState<ScheduledView>('list')
  const [backlogSort, setBacklogSort] = useState<BacklogSort>('manual')
  const [draggedBacklogId, setDraggedBacklogId] = useState<string | null>(null)
  const [draggedScheduledId, setDraggedScheduledId] = useState<string | null>(null)
  const [listDragOver, setListDragOver] = useState(false)
  const [backlogDragOver, setBacklogDragOver] = useState(false)
  const backlogRef = useRef<HTMLUListElement>(null)

  const viewingToday = isSameDay(selectedDate, new Date())

  // Open, dated items grouped by day — drives both the density dots (Week/
  // Quarter/Year) and the inline title previews (Month) in DateNavigator.
  const itemsByDay = useMemo(() => {
    const map = new Map<string, DomainItem[]>()
    for (const item of items) {
      if (item.kind === 'habitInstance' || item.completion.type !== 'open') continue
      const d = anchorSortDate(item.anchor)
      if (!d) continue
      const key = startOfDay(d).toDateString()
      const list = map.get(key)
      if (list) list.push(item)
      else map.set(key, [item])
    }
    for (const list of map.values()) {
      list.sort((a, b) => anchorSortDate(a.anchor)!.getTime() - anchorSortDate(b.anchor)!.getTime())
    }
    return map
  }, [items])

  const dayItems = items.filter((item) => {
    if (item.kind === 'habitInstance') return false // renders on Habits instead
    const d = anchorSortDate(item.anchor)
    return d ? isSameDay(d, selectedDate) : false
  })

  const scheduled = dayItems
    .filter((i) => i.completion.type === 'open')
    .sort((a, b) => {
      const diff = anchorSortDate(a.anchor)!.getTime() - anchorSortDate(b.anchor)!.getTime()
      return diff !== 0 ? diff : anchorSortPriority(a.anchor) - anchorSortPriority(b.anchor)
    })

  // Not day-scoped at all — untimed items have no date to filter by, so
  // this is the same list regardless of which day is selected above (see
  // the module doc comment).
  const backlogUnsorted = items.filter((i) => i.kind !== 'habitInstance' && anchorIsUntimed(i.anchor) && i.completion.type === 'open')
  const backlog =
    backlogSort === 'project'
      ? [...backlogUnsorted].sort((a, b) => {
          const pa = a.tags[0]?.name ?? ''
          const pb = b.tags[0]?.name ?? ''
          if (pa === pb) return 0
          if (pa === '') return 1
          if (pb === '') return -1
          return pa.localeCompare(pb)
        })
      : backlogUnsorted

  const completed = dayItems.filter((i) => i.completion.type !== 'open')

  const isEmpty = scheduled.length === 0 && backlog.length === 0 && completed.length === 0
  // Scheduled and Backlog both need to stay visible (and droppable)
  // whenever there's anything in EITHER one — dragging between them needs
  // a source AND a target, so hiding one just because it's momentarily
  // empty would remove the only place to drop into it.
  const showScheduledSection = scheduled.length > 0 || backlog.length > 0
  const showBacklogSection = scheduled.length > 0 || backlog.length > 0

  function handleBacklogDragStart(e: DragEvent<HTMLLIElement>, item: DomainItem) {
    e.dataTransfer.setData('text/plain', item.id)
    e.dataTransfer.effectAllowed = 'move'
    setDraggedBacklogId(item.id)
  }

  function handleBacklogDragEnd() {
    setDraggedBacklogId(null)
    setListDragOver(false)
  }

  function handleScheduledDragStart(e: DragEvent<HTMLLIElement>, item: DomainItem) {
    e.dataTransfer.setData('text/plain', item.id)
    e.dataTransfer.effectAllowed = 'move'
    setDraggedScheduledId(item.id)
  }

  function handleScheduledDragEnd() {
    setDraggedScheduledId(null)
    setBacklogDragOver(false)
  }

  /** Shared by both ways a scheduled item can land back in the backlog:
   *  HTML5 DnD from the List view (handleBacklogZoneDrop) and the
   *  Timeline's own pointer-drag hit-testing against backlogRef
   *  (DayTimeline's onUnschedule). */
  function unschedule(itemId: string) {
    const item = items.find((i) => i.id === itemId)
    if (!item) return
    void updateItem({ ...item, anchor: { type: 'untimed' } })
  }

  function handleBacklogZoneDrop(e: DragEvent<HTMLUListElement>) {
    e.preventDefault()
    setBacklogDragOver(false)
    const id = e.dataTransfer.getData('text/plain')
    if (id) unschedule(id)
  }

  /** Where a task dropped onto the LIST view (as opposed to a specific Y
   *  position on the timeline) should start: right after the last scheduled
   *  item's actual end (anchorEndDate — a timeBlock's real end, not just its
   *  start), or a sensible default when nothing's scheduled yet. */
  function nextAvailableStart(): Date {
    const last = scheduled[scheduled.length - 1]
    const afterLast = last ? anchorEndDate(last.anchor) : undefined
    if (afterLast) return afterLast

    const fallback = new Date(selectedDate)
    if (viewingToday) {
      const now = new Date()
      fallback.setHours(now.getHours(), now.getMinutes(), 0, 0)
      const remainder = fallback.getMinutes() % 15
      if (remainder !== 0) fallback.setMinutes(fallback.getMinutes() + (15 - remainder))
    } else {
      fallback.setHours(9, 0, 0, 0)
    }
    return fallback
  }

  function handleDropOnList(e: DragEvent<HTMLUListElement>) {
    e.preventDefault()
    setListDragOver(false)
    const id = e.dataTransfer.getData('text/plain')
    const item = items.find((i) => i.id === id)
    if (!item) return
    void updateItem({ ...item, anchor: { type: 'dueAt', date: nextAvailableStart().toISOString() } })
  }

  function handleDropOnTimeline(itemId: string, minutesSinceMidnight: number) {
    const item = items.find((i) => i.id === itemId)
    if (!item) return
    const target = new Date(selectedDate)
    target.setHours(0, minutesSinceMidnight, 0, 0)
    void updateItem({ ...item, anchor: { type: 'dueAt', date: target.toISOString() } })
  }

  return (
    <div className="p-6">
      <h1 className="mb-4 text-xl font-semibold text-text-primary">Today</h1>

      <DateNavigator selectedDate={selectedDate} onSelectDate={setSelectedDate} itemsByDay={itemsByDay} />

      <QuickAddSection defaultDate={selectedDate} />

      {!initialLoadComplete && <p className="text-sm text-text-secondary">Loading…</p>}

      {initialLoadComplete && isEmpty && (
        <p className="text-sm text-text-secondary">
          {viewingToday ? 'Nothing today. Capture anything you owe your future self.' : 'Nothing scheduled for this day.'}
        </p>
      )}

      {/* Two-column layout on wide viewports: Scheduled gets the lion's
          share of the width since it's the primary "what does my day look
          like" view (especially the Timeline), while Backlog/Completed sit
          in a narrower side column. Collapses to a single stacked column
          below the lg breakpoint. */}
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[2fr_1fr]">
        {showScheduledSection && (
          <section className="min-w-0">
            <div className="mb-2 flex items-center justify-between">
              <h2 className="text-xs font-medium uppercase tracking-wide text-text-secondary">
                Scheduled — {scheduled.length}
              </h2>
              <div className="flex gap-1 rounded-leo-md bg-surface-elevated p-1">
                {(['list', 'timeline'] as const).map((v) => (
                  <button
                    key={v}
                    type="button"
                    onClick={() => setScheduledView(v)}
                    aria-pressed={scheduledView === v}
                    className={cn(
                      'rounded-leo-sm px-2.5 py-1 text-xs font-medium capitalize transition-colors',
                      scheduledView === v ? 'bg-surface text-text-primary shadow-sm' : 'text-text-secondary hover:text-text-primary',
                    )}
                  >
                    {v}
                  </button>
                ))}
              </div>
            </div>
            {scheduledView === 'timeline' ? (
              <DayTimeline
                items={scheduled}
                date={selectedDate}
                onDropItem={handleDropOnTimeline}
                onUnschedule={unschedule}
                backlogDropZoneRef={backlogRef}
                onHoverBacklogChange={setBacklogDragOver}
              />
            ) : (
              <ul
                onDragOver={(e) => {
                  e.preventDefault()
                  e.dataTransfer.dropEffect = 'move'
                  if (!listDragOver) setListDragOver(true)
                }}
                onDragLeave={() => setListDragOver(false)}
                onDrop={handleDropOnList}
                className={cn(
                  'flex min-h-12 flex-col gap-2 rounded-leo-md border-2 border-dashed p-1 transition-colors',
                  listDragOver ? 'border-accent bg-accent-muted/20' : 'border-transparent',
                )}
              >
                {scheduled.length === 0 && (
                  <p className="p-2 text-xs text-text-secondary">Drag a backlog task here to schedule it right after your last item.</p>
                )}
                {scheduled.map((item) => (
                  <ItemRow
                    key={item.id}
                    item={item}
                    draggable={!isExternallyManaged(item)}
                    onDragStart={(e) => handleScheduledDragStart(e, item)}
                    onDragEnd={handleScheduledDragEnd}
                    className={item.id === draggedScheduledId ? 'opacity-40' : undefined}
                  />
                ))}
              </ul>
            )}
          </section>
        )}

        <div className="flex min-w-0 flex-col gap-6">
          {showBacklogSection && (
            <section>
              <div className="mb-2 flex items-center justify-between">
                <h2 className="text-xs font-medium uppercase tracking-wide text-text-secondary">
                  Backlog — {backlog.length}
                </h2>
                <div className="flex gap-1 rounded-leo-md bg-surface-elevated p-1">
                  {([
                    { value: 'manual', label: 'Manual' },
                    { value: 'project', label: 'Project' },
                  ] as const).map((opt) => (
                    <button
                      key={opt.value}
                      type="button"
                      onClick={() => setBacklogSort(opt.value)}
                      aria-pressed={backlogSort === opt.value}
                      className={cn(
                        'rounded-leo-sm px-2.5 py-1 text-xs font-medium transition-colors',
                        backlogSort === opt.value ? 'bg-surface text-text-primary shadow-sm' : 'text-text-secondary hover:text-text-primary',
                      )}
                    >
                      {opt.label}
                    </button>
                  ))}
                </div>
              </div>
              <ul
                ref={backlogRef}
                onDragOver={(e) => {
                  e.preventDefault()
                  e.dataTransfer.dropEffect = 'move'
                  if (!backlogDragOver) setBacklogDragOver(true)
                }}
                onDragLeave={() => setBacklogDragOver(false)}
                onDrop={handleBacklogZoneDrop}
                className={cn(
                  'flex min-h-12 flex-col gap-2 rounded-leo-md border-2 border-dashed p-1 transition-colors',
                  backlogDragOver ? 'border-accent bg-accent-muted/20' : 'border-transparent',
                )}
              >
                {backlog.length === 0 && (
                  <p className="p-2 text-xs text-text-secondary">Drag a scheduled item here to move it back to the backlog.</p>
                )}
                {backlog.map((item) => (
                  <ItemRow
                    key={item.id}
                    item={item}
                    draggable={!isExternallyManaged(item)}
                    onDragStart={(e) => handleBacklogDragStart(e, item)}
                    onDragEnd={handleBacklogDragEnd}
                    className={item.id === draggedBacklogId ? 'opacity-40' : undefined}
                  />
                ))}
              </ul>
            </section>
          )}

          {completed.length > 0 && (
            <section>
              <h2 className="mb-2 text-xs font-medium uppercase tracking-wide text-text-secondary">
                Completed — {completed.length}
              </h2>
              <ul className="flex flex-col gap-2">
                {completed.map((item) => (
                  <ItemRow key={item.id} item={item} />
                ))}
              </ul>
            </section>
          )}
        </div>
      </div>
    </div>
  )
}
