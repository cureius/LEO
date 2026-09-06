import { useEffect, useMemo, useRef, useState, type DragEvent } from 'react'
import { Bell, Calendar, CheckCircle2, Circle, Dumbbell, UtensilsCrossed } from 'lucide-react'
import { updateItem, toggleComplete } from '@/sync/mutations'
import { isExternallyManaged } from '@/wire/items'
import { shiftAnchorMinutes, type Anchor } from '@/wire/anchor'
import { completionIconFor, kindLabel, type CompletionIconKind } from '@/domain/itemDisplay'
import { ItemDetailPanel } from './ItemDetailPanel'
import type { DomainItem } from '@/domain/types'

const ICONS: Record<CompletionIconKind, typeof Circle> = {
  bell: Bell,
  bellOff: Bell,
  circleDot: Circle,
  circleFilled: CheckCircle2,
  calendar: Calendar,
  calendarCheck: CheckCircle2,
  dumbbell: Dumbbell,
  utensils: UtensilsCrossed,
  checkCircle: CheckCircle2,
  circle: Circle,
}

const HOUR_HEIGHT = 60 // px per hour == 1px per minute
const PX_PER_MIN = HOUR_HEIGHT / 60
const SNAP_MINUTES = 15
const MINUTES_PER_DAY = 24 * 60
const POINT_VISUAL_MINUTES = 30 // fixed visual duration for dueAt/point pills — layout only, not stored
const DRAG_CLICK_THRESHOLD_PX = 5

function minutesSinceMidnight(d: Date): number {
  return d.getHours() * 60 + d.getMinutes()
}

function formatClock(totalMinutes: number): string {
  const m = ((totalMinutes % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY
  const h = Math.floor(m / 60)
  const min = m % 60
  const period = h < 12 ? 'AM' : 'PM'
  const h12 = h % 12 === 0 ? 12 : h % 12
  return `${h12}:${String(min).padStart(2, '0')} ${period}`
}

type TimedEntry = {
  item: DomainItem
  startMin: number
  endMin: number
  isPoint: boolean
}

function toTimedEntry(item: DomainItem): TimedEntry | null {
  const a = item.anchor
  if (a.type === 'dueAt' || a.type === 'point') {
    const startMin = minutesSinceMidnight(new Date(a.date))
    return { item, startMin, endMin: Math.min(startMin + POINT_VISUAL_MINUTES, MINUTES_PER_DAY), isPoint: true }
  }
  if (a.type === 'timeBlock') {
    const start = new Date(a.start)
    const end = new Date(a.end)
    const startMin = minutesSinceMidnight(start)
    const sameDay = start.getFullYear() === end.getFullYear() && start.getMonth() === end.getMonth() && start.getDate() === end.getDate()
    const rawEndMin = sameDay ? minutesSinceMidnight(end) : MINUTES_PER_DAY
    const endMin = Math.max(rawEndMin, startMin + 20) // minimum visual height so short blocks stay tappable
    return { item, startMin, endMin: Math.min(endMin, MINUTES_PER_DAY), isPoint: false }
  }
  return null // untimed / location — no time to position on a timeline
}

/**
 * Greedy interval-column packing (the standard day-calendar layout
 * algorithm): overlapping items are placed in side-by-side columns instead
 * of stacking on top of each other. Not guaranteed minimal-width-optimal for
 * pathological overlap patterns, but correct and stable for normal days.
 */
function computeColumns(entries: TimedEntry[]): Map<string, { col: number; numCols: number }> {
  const sorted = [...entries].sort((a, b) => a.startMin - b.startMin || a.endMin - b.endMin)
  type Active = { id: string; col: number; endMin: number }
  let active: Active[] = []
  let cluster: Active[] = []
  const clusters: Active[][] = []
  const colById = new Map<string, number>()

  function flushCluster() {
    if (cluster.length > 0) clusters.push(cluster)
    cluster = []
  }

  for (const e of sorted) {
    active = active.filter((a) => a.endMin > e.startMin)
    if (active.length === 0) flushCluster()
    const usedCols = new Set(active.map((a) => a.col))
    let col = 0
    while (usedCols.has(col)) col++
    const entry: Active = { id: e.item.id, col, endMin: e.endMin }
    active.push(entry)
    cluster.push(entry)
    colById.set(e.item.id, col)
  }
  flushCluster()

  const numColsById = new Map<string, number>()
  for (const cl of clusters) {
    const numCols = Math.max(...cl.map((c) => c.col)) + 1
    for (const c of cl) numColsById.set(c.id, numCols)
  }

  const layout = new Map<string, { col: number; numCols: number }>()
  for (const [id, col] of colById) layout.set(id, { col, numCols: numColsById.get(id) ?? 1 })
  return layout
}

type DragState = { id: string; pointerId: number; startClientY: number; deltaMin: number; movedPx: number }

function isPointInRect(x: number, y: number, rect: DOMRect): boolean {
  return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom
}

/**
 * Drag-to-reschedule day timeline for the Today page's "Scheduled" section.
 * Vertical drag changes an item's time (snapped to 15-minute increments,
 * clamped to the visible day); duration is preserved for timeBlock items.
 * Externally-managed (EventKit-mirrored) items render but are not
 * draggable — same read-only rule as everywhere else in the app.
 *
 * `onDropItem` is a SEPARATE drag system from the reschedule-by-dragging-
 * an-existing-block above — that one uses raw Pointer Events (setPointerCapture
 * on each block); this is the native HTML5 Drag and Drop API, used by
 * TodayPage.tsx's Backlog rows (see ItemRow's `draggable` prop) to drop a
 * not-yet-scheduled item onto a specific time. The two coexist without
 * conflict since a drag always starts from one or the other, never both.
 *
 * `onUnschedule`/`backlogDropZoneRef`/`onHoverBacklogChange` extend the
 * EXISTING pointer-based reschedule drag rather than adding a third,
 * HTML5-draggable-based system on the same block — giving a timeline block
 * both `draggable` and pointer handlers on one element would race the
 * browser's native drag start against setPointerCapture. Instead,
 * `setPointerCapture` already routes every pointermove/pointerup to this
 * block regardless of where the cursor physically is, so dragging out of
 * the timeline and releasing over the Backlog list (identified via a DOM
 * ref TodayPage hands down) is just a hit-test at release time — no second
 * drag system needed. */
export function DayTimeline({
  items,
  date,
  onDropItem,
  onUnschedule,
  backlogDropZoneRef,
  onHoverBacklogChange,
}: {
  items: DomainItem[]
  date: Date
  onDropItem?: (itemId: string, minutesSinceMidnight: number) => void
  onUnschedule?: (itemId: string) => void
  backlogDropZoneRef?: React.RefObject<HTMLElement | null>
  onHoverBacklogChange?: (isOver: boolean) => void
}) {
  const isToday = useMemo(() => {
    const now = new Date()
    return now.getFullYear() === date.getFullYear() && now.getMonth() === date.getMonth() && now.getDate() === date.getDate()
  }, [date])

  const [nowMinutes, setNowMinutes] = useState(() => minutesSinceMidnight(new Date()))
  useEffect(() => {
    if (!isToday) return
    const id = setInterval(() => setNowMinutes(minutesSinceMidnight(new Date())), 60_000)
    return () => clearInterval(id)
  }, [isToday])

  const entries = useMemo(() => items.map(toTimedEntry).filter((e): e is TimedEntry => e !== null), [items])
  const columns = useMemo(() => computeColumns(entries), [entries])

  const [drag, setDrag] = useState<DragState | null>(null)
  const [detailItem, setDetailItem] = useState<DomainItem | null>(null)
  const [externalDragOver, setExternalDragOver] = useState(false)
  const scrollRef = useRef<HTMLDivElement>(null)
  const scrolledOnceRef = useRef(false)
  const hoveringBacklogRef = useRef(false)

  function handleContainerDragOver(e: DragEvent<HTMLDivElement>) {
    if (!onDropItem) return
    e.preventDefault()
    e.dataTransfer.dropEffect = 'move'
    if (!externalDragOver) setExternalDragOver(true)
  }

  function handleContainerDrop(e: DragEvent<HTMLDivElement>) {
    setExternalDragOver(false)
    if (!onDropItem) return
    e.preventDefault()
    const itemId = e.dataTransfer.getData('text/plain')
    if (!itemId) return
    const rect = e.currentTarget.getBoundingClientRect()
    const offsetY = e.clientY - rect.top + e.currentTarget.scrollTop
    let minutes = Math.round(offsetY / PX_PER_MIN)
    minutes = Math.round(minutes / SNAP_MINUTES) * SNAP_MINUTES
    minutes = Math.max(0, Math.min(MINUTES_PER_DAY - SNAP_MINUTES, minutes))
    onDropItem(itemId, minutes)
  }

  useEffect(() => {
    if (scrolledOnceRef.current || !scrollRef.current) return
    scrolledOnceRef.current = true
    const target = isToday ? nowMinutes : (entries[0]?.startMin ?? 8 * 60)
    scrollRef.current.scrollTop = Math.max(0, (target - 90) * PX_PER_MIN)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  function handlePointerDown(e: React.PointerEvent<HTMLDivElement>, item: DomainItem) {
    if (isExternallyManaged(item)) return
    e.currentTarget.setPointerCapture(e.pointerId)
    setDrag({ id: item.id, pointerId: e.pointerId, startClientY: e.clientY, deltaMin: 0, movedPx: 0 })
  }

  function handlePointerMove(e: React.PointerEvent<HTMLDivElement>, entry: TimedEntry) {
    if (!drag || drag.id !== entry.item.id) return
    const movedPx = e.clientY - drag.startClientY
    const rawDeltaMin = movedPx / PX_PER_MIN
    let deltaMin = Math.round(rawDeltaMin / SNAP_MINUTES) * SNAP_MINUTES
    const duration = entry.endMin - entry.startMin
    const minDelta = -entry.startMin
    const maxDelta = MINUTES_PER_DAY - duration - entry.startMin
    deltaMin = Math.max(minDelta, Math.min(maxDelta, deltaMin))
    setDrag({ ...drag, deltaMin, movedPx })

    if (backlogDropZoneRef?.current) {
      const isOver = isPointInRect(e.clientX, e.clientY, backlogDropZoneRef.current.getBoundingClientRect())
      if (isOver !== hoveringBacklogRef.current) {
        hoveringBacklogRef.current = isOver
        onHoverBacklogChange?.(isOver)
      }
    }
  }

  function handlePointerUp(e: React.PointerEvent<HTMLDivElement>, entry: TimedEntry) {
    if (!drag || drag.id !== entry.item.id) return
    e.currentTarget.releasePointerCapture(e.pointerId)
    const { deltaMin, movedPx } = drag
    const droppedOnBacklog = hoveringBacklogRef.current
    hoveringBacklogRef.current = false
    onHoverBacklogChange?.(false)
    setDrag(null)
    if (Math.abs(movedPx) < DRAG_CLICK_THRESHOLD_PX) {
      setDetailItem(entry.item)
      return
    }
    if (droppedOnBacklog) {
      onUnschedule?.(entry.item.id)
      return
    }
    if (deltaMin === 0) return
    const newAnchor: Anchor = shiftAnchorMinutes(entry.item.anchor, deltaMin)
    void updateItem({ ...entry.item, anchor: newAnchor })
  }

  const hours = Array.from({ length: 24 }, (_, h) => h)

  return (
    <>
      <div
        ref={scrollRef}
        onDragOver={handleContainerDragOver}
        onDragLeave={() => setExternalDragOver(false)}
        onDrop={handleContainerDrop}
        className={`relative max-h-[560px] overflow-y-auto rounded-leo-md border-2 bg-surface transition-colors ${
          externalDragOver ? 'border-accent bg-accent-muted/20' : 'border-divider'
        }`}
        role="list"
        aria-label="Day timeline — drag an item to reschedule its time, or drop a backlog task here to schedule it"
      >
        <div className="relative flex" style={{ height: MINUTES_PER_DAY * PX_PER_MIN }}>
          <div className="sticky left-0 w-14 shrink-0 border-r border-divider bg-surface">
            {hours.map((h) => (
              <div
                key={h}
                className="absolute right-2 -translate-y-1/2 text-[11px] text-text-secondary"
                style={{ top: h * HOUR_HEIGHT }}
              >
                {h === 0 ? '' : formatClock(h * 60).replace(':00', '')}
              </div>
            ))}
          </div>

          <div className="relative flex-1">
            {hours.map((h) => (
              <div key={h} className="absolute inset-x-0 border-t border-divider/70" style={{ top: h * HOUR_HEIGHT }} />
            ))}

            {isToday && nowMinutes >= 0 && nowMinutes <= MINUTES_PER_DAY && (
              <div
                className="pointer-events-none absolute inset-x-0 z-20 flex items-center gap-1"
                style={{ top: nowMinutes * PX_PER_MIN }}
              >
                <div className="h-1.5 w-1.5 shrink-0 rounded-full bg-danger" />
                <div className="h-px flex-1 bg-danger" />
              </div>
            )}

            {entries.map((entry) => {
              const { item } = entry
              const layout = columns.get(item.id) ?? { col: 0, numCols: 1 }
              const readOnly = isExternallyManaged(item)
              const done = item.completion.type !== 'open'
              const Icon = ICONS[completionIconFor(item)]
              const isDragging = drag?.id === item.id
              const shownStartMin = isDragging ? entry.startMin + drag.deltaMin : entry.startMin
              const widthPct = 100 / layout.numCols
              const leftPct = layout.col * widthPct

              return (
                <div
                  key={item.id}
                  role="listitem"
                  onPointerDown={(e) => handlePointerDown(e, item)}
                  onPointerMove={(e) => handlePointerMove(e, entry)}
                  onPointerUp={(e) => handlePointerUp(e, entry)}
                  className={`absolute overflow-hidden rounded-leo-sm border px-2 py-1 text-left transition-shadow ${
                    done
                      ? 'border-divider bg-surface-elevated text-text-secondary'
                      : 'border-accent/30 bg-accent-muted text-text-primary'
                  } ${readOnly ? 'cursor-pointer opacity-70' : 'cursor-grab active:cursor-grabbing'} ${
                    isDragging ? 'z-30 shadow-lg ring-2 ring-accent' : 'z-10'
                  }`}
                  style={{
                    top: shownStartMin * PX_PER_MIN,
                    height: Math.max((entry.endMin - entry.startMin) * PX_PER_MIN, 20),
                    left: `calc(${leftPct}% + 2px)`,
                    width: `calc(${widthPct}% - 4px)`,
                    touchAction: 'none',
                  }}
                >
                  <div className="flex items-center gap-1">
                    {/* stopPropagation on both pointerdown and click — the
                        parent handles pointerdown to start a reschedule
                        drag and pointerup-with-no-movement to open the
                        detail modal; without stopping it here, tapping this
                        toggle would ALSO fire one of those. */}
                    <button
                      type="button"
                      onPointerDown={(e) => e.stopPropagation()}
                      onClick={(e) => {
                        e.stopPropagation()
                        if (!readOnly) void toggleComplete(item)
                      }}
                      disabled={readOnly}
                      aria-label={done ? `Mark "${item.title}" not done` : `Mark "${item.title}" done`}
                      className={`shrink-0 rounded-full ${readOnly ? 'cursor-not-allowed' : 'hover:bg-surface'}`}
                    >
                      <Icon className={`h-3 w-3 ${done ? 'text-success' : 'text-accent'}`} strokeWidth={2.5} />
                    </button>
                    <span className={`truncate text-xs font-medium ${done ? 'line-through' : ''}`}>{item.title}</span>
                  </div>
                  <span className="block text-[10px] text-text-secondary">
                    {isDragging ? formatClock(shownStartMin) : `${formatClock(entry.startMin)} · ${kindLabel(item.kind)}`}
                    {readOnly && ' · Synced'}
                  </span>
                </div>
              )
            })}
          </div>
        </div>
      </div>

      {detailItem && <ItemDetailPanel item={detailItem} onClose={() => setDetailItem(null)} />}
    </>
  )
}
