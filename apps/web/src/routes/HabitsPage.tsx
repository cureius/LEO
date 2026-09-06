import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { useShallow } from 'zustand/react/shallow'
import { Archive, ArchiveRestore, Flame, Trash2 } from 'lucide-react'
import { HabitCreateForm } from '@/components/habits/HabitCreateForm'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { selectHabitsArray, selectItemsArray, useSyncStore } from '@/sync/store'
import { addItem, deleteHabit, setHabitArchived, toggleComplete } from '@/sync/mutations'
import { materializeHabit, anchorDateFor } from '@/recurrence/habitMaterializer'
import { currentStreakDays } from '@/domain/streak'
import { anchorSortDate } from '@/wire/anchor'
import type { Habit, HabitInstanceItem } from '@/domain/types'

const NAME_COLUMN_WIDTH = 200
const DAY_COLUMN_WIDTH = 40
const HEADER_HEIGHT = 40
const ROW_HEIGHT = 52
// However many days fit on screen, the grid renders this many screens'
// worth of history so there's real scrollable backlog behind "today"
// instead of stopping right where the visible area does.
const SCREENS_OF_HISTORY = 6
const MIN_DAYS = 30

function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}
function addDays(date: Date, n: number): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + n)
}
function dayKey(date: Date): number {
  return startOfDay(date).getTime()
}
function isSameDay(a: Date, b: Date): boolean {
  return dayKey(a) === dayKey(b)
}

const WEEKDAY_FORMAT = new Intl.DateTimeFormat(undefined, { weekday: 'short' })

function frequencyLabel(habit: { frequency: { type: string; days?: string[] } }): string {
  if (habit.frequency.type === 'daily') return 'Every day'
  if (habit.frequency.type === 'specificDays') return (habit.frequency.days ?? []).join(', ')
  return habit.frequency.type
}

/**
 * A day-by-day tracker grid (habits × dates), not just "today's checkbox" —
 * the point is letting the user page backward and tap a past day to log a
 * habit they actually did but forgot to check off at the time. Clicking a
 * day with no instance yet creates one straight into "completed" (the whole
 * reason to click a PAST day is to log it done, unlike today's cell, which
 * toggles); clicking a day that already has an instance just toggles it,
 * same as everywhere else habit instances are checked off.
 */
export function HabitsPage() {
  const habits = useSyncStore(useShallow(selectHabitsArray))
  const items = useSyncStore(useShallow(selectItemsArray))
  const initialLoadComplete = useSyncStore((s) => s.initialLoadComplete)

  const scrollRef = useRef<HTMLDivElement>(null)
  const namesRef = useRef<HTMLDivElement>(null)
  const syncingScrollRef = useRef(false)
  const [visibleColumns, setVisibleColumns] = useState(14)

  // The day grid scrolls both ways (CSS `sticky left-0` proved unreliable
  // for the name column in the Tauri WKWebView shell — it kept scrolling
  // out of view instead of pinning), so the name column is instead a
  // wholly separate, horizontally-static panel whose vertical scroll is
  // kept in lockstep with the day grid's here. The guard flag stops the
  // two onScroll handlers from bouncing off each other.
  function handleDaysScroll() {
    if (syncingScrollRef.current) {
      syncingScrollRef.current = false
      return
    }
    if (namesRef.current && scrollRef.current) {
      syncingScrollRef.current = true
      namesRef.current.scrollTop = scrollRef.current.scrollTop
    }
  }
  function handleNamesScroll() {
    if (syncingScrollRef.current) {
      syncingScrollRef.current = false
      return
    }
    if (scrollRef.current && namesRef.current) {
      syncingScrollRef.current = true
      scrollRef.current.scrollTop = namesRef.current.scrollTop
    }
  }

  // Sizes the grid to the actual viewport instead of a hardcoded day count —
  // measures the day panel's own width (the name panel is a separate,
  // fixed-width sibling now, not part of this element) and derives how many
  // DAY_COLUMN_WIDTH columns fit.
  useLayoutEffect(() => {
    const el = scrollRef.current
    if (!el) return
    const observer = new ResizeObserver((entries) => {
      const width = entries[0]?.contentRect.width ?? el.clientWidth
      const fit = Math.floor(width / DAY_COLUMN_WIDTH)
      setVisibleColumns(Math.max(7, fit))
    })
    observer.observe(el)
    return () => observer.disconnect()
  }, [])

  const totalDays = Math.max(MIN_DAYS, visibleColumns * SCREENS_OF_HISTORY)

  // Scrolled to the far right by default so "today" is the first thing
  // visible — older days live to the left, reached by scrolling, exactly
  // like the rest of the app's continuous-scroll surfaces (see PdfViewer).
  useEffect(() => {
    const el = scrollRef.current
    if (el) el.scrollLeft = el.scrollWidth
  }, [totalDays])

  // Materialize instances for every active habit once the initial load has
  // settled and whenever the habit list changes (e.g. a new habit was just
  // created). Safe to re-run repeatedly — materializeHabit is idempotent by
  // construction (HabitMaterializer's own dedup-by-day logic), so this
  // never creates duplicates even if the effect fires more than once.
  const materializedForRef = useRef<string>('')
  useEffect(() => {
    if (!initialLoadComplete) return
    const active = habits.filter((h) => !h.isArchived)
    const key = active.map((h) => h.id).join(',')
    if (key === materializedForRef.current) return
    materializedForRef.current = key
    for (const habit of active) void materializeHabit(habit)
  }, [habits, initialLoadComplete])

  const today = startOfDay(new Date())
  const days = Array.from({ length: totalDays }, (_, i) => addDays(today, -(totalDays - 1 - i)))

  // habitId -> dayKey -> instance, plus a flat per-habit list (for streaks,
  // which want every instance regardless of what's currently on-screen).
  const instancesByHabit = new Map<string, HabitInstanceItem[]>()
  const instanceByHabitAndDay = new Map<string, Map<number, HabitInstanceItem>>()
  for (const item of items) {
    if (item.kind !== 'habitInstance') continue
    const list = instancesByHabit.get(item.habitID) ?? []
    list.push(item)
    instancesByHabit.set(item.habitID, list)

    const sortDate = anchorSortDate(item.anchor)
    if (!sortDate) continue
    let byDay = instanceByHabitAndDay.get(item.habitID)
    if (!byDay) {
      byDay = new Map()
      instanceByHabitAndDay.set(item.habitID, byDay)
    }
    // Prefer a non-open instance over an open one for the same day, in the
    // rare case both exist — a resolved instance is the one worth showing.
    const existing = byDay.get(dayKey(sortDate))
    if (!existing || existing.completion.type === 'open') byDay.set(dayKey(sortDate), item)
  }

  async function handleCellClick(habit: Habit, date: Date) {
    const existing = instanceByHabitAndDay.get(habit.id)?.get(dayKey(date))
    if (existing) {
      void toggleComplete(existing)
      return
    }
    const now = new Date()
    const instance: HabitInstanceItem = {
      kind: 'habitInstance',
      id: crypto.randomUUID(),
      title: habit.name,
      createdAt: now,
      updatedAt: now,
      importance: 1,
      anchor: anchorDateFor(habit, date),
      completion: { type: 'completed', date: now.toISOString() },
      habitID: habit.id,
      targetDurationSeconds: habit.targetDurationSeconds,
    }
    await addItem(instance)
  }

  const active = habits.filter((h) => !h.isArchived)
  const archived = habits.filter((h) => h.isArchived)

  return (
    <div className="flex h-full flex-col p-6">
      <h1 className="mb-1 shrink-0 text-xl font-semibold text-text-primary">Habits</h1>
      <p className="mb-4 shrink-0 text-sm text-text-secondary">
        Track recurring activities to build streaks. Click any day — including past ones — to log or unlog it.
      </p>

      <div className="shrink-0">
        <HabitCreateForm />
      </div>

      {!initialLoadComplete && <p className="text-sm text-text-secondary">Loading…</p>}

      {initialLoadComplete && active.length === 0 && (
        <p className="text-sm text-text-secondary">No habits yet — create one above.</p>
      )}

      {active.length > 0 && (
        <div className="mt-2 flex min-h-0 flex-1 flex-col">
          <div className="mb-2 flex shrink-0 items-center gap-2">
            <span className="text-xs text-text-secondary">
              {days[0].toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })} – Today
            </span>
            <Button variant="ghost" size="sm" onClick={() => scrollRef.current?.scrollTo({ left: scrollRef.current.scrollWidth, behavior: 'smooth' })}>
              Jump to today
            </Button>
          </div>

          <div className="flex min-h-0 flex-1 overflow-hidden rounded-leo-md border border-divider">
            {/* Frozen name column — a separate panel, not `sticky`, so its
                position can never be affected by the day grid's own
                horizontal scrolling. Only scrolls vertically, kept in sync
                with the day grid below via handleNamesScroll/handleDaysScroll. */}
            <div className="flex shrink-0 flex-col border-r border-divider" style={{ width: NAME_COLUMN_WIDTH }}>
              <div className="shrink-0 border-b border-divider bg-surface" style={{ height: HEADER_HEIGHT }} />
              <div ref={namesRef} onScroll={handleNamesScroll} className="min-h-0 flex-1 overflow-y-auto overflow-x-hidden">
                {active.map((habit) => {
                  const streak = currentStreakDays(instancesByHabit.get(habit.id) ?? [], today)
                  return (
                    <div
                      key={habit.id}
                      className="flex items-center gap-2 border-b border-divider bg-surface px-2 py-1.5"
                      style={{ height: ROW_HEIGHT }}
                    >
                      <div className="flex min-w-0 flex-1 flex-col">
                        <span className="truncate text-sm font-medium text-text-primary">{habit.name}</span>
                        <span className="truncate text-[11px] text-text-secondary">{frequencyLabel(habit)}</span>
                      </div>
                      {streak > 0 && (
                        <span className="flex shrink-0 items-center gap-0.5 text-xs font-medium text-warning" title={`${streak}-day streak`}>
                          <Flame className="h-3 w-3 fill-current" />
                          {streak}
                        </span>
                      )}
                      <Button
                        variant="ghost"
                        size="icon-xs"
                        aria-label={`Archive "${habit.name}"`}
                        className="shrink-0"
                        onClick={() => void setHabitArchived(habit, true)}
                      >
                        <Archive className="h-3.5 w-3.5" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon-xs"
                        aria-label={`Delete "${habit.name}"`}
                        className="shrink-0 text-text-secondary hover:text-danger"
                        onClick={() => void deleteHabit(habit, instancesByHabit.get(habit.id) ?? [])}
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </Button>
                    </div>
                  )
                })}
              </div>
            </div>

            {/* Day grid — the only horizontally-scrolling part. */}
            <div ref={scrollRef} onScroll={handleDaysScroll} className="min-h-0 flex-1 overflow-auto">
              <div style={{ width: totalDays * DAY_COLUMN_WIDTH }}>
                <div className="sticky top-0 z-10 flex bg-surface" style={{ height: HEADER_HEIGHT }}>
                  {days.map((date) => {
                    const isToday = isSameDay(date, today)
                    return (
                      <div
                        key={dayKey(date)}
                        className={cn(
                          'flex shrink-0 flex-col items-center justify-center border-b border-divider text-[10px]',
                          isToday && 'bg-accent-muted',
                        )}
                        style={{ width: DAY_COLUMN_WIDTH }}
                      >
                        <span className="text-text-secondary uppercase">{WEEKDAY_FORMAT.format(date).slice(0, 2)}</span>
                        <span className={cn('font-medium', isToday ? 'text-accent' : 'text-text-primary')}>{date.getDate()}</span>
                      </div>
                    )
                  })}
                </div>

                {active.map((habit) => {
                  const createdDay = dayKey(startOfDay(habit.createdAt))
                  return (
                    <div key={habit.id} className="flex" style={{ height: ROW_HEIGHT }}>
                      {days.map((date) => {
                        const key = dayKey(date)
                        const instance = instanceByHabitAndDay.get(habit.id)?.get(key)
                        const done = instance && instance.completion.type !== 'open'
                        const disabled = key < createdDay || key > dayKey(today)
                        const isToday = isSameDay(date, today)
                        return (
                          <div
                            key={`${habit.id}-${key}`}
                            className={cn(
                              'flex shrink-0 items-center justify-center border-r border-b border-divider',
                              isToday && 'bg-accent-muted/30',
                            )}
                            style={{ width: DAY_COLUMN_WIDTH }}
                          >
                            <button
                              type="button"
                              disabled={disabled}
                              onClick={() => void handleCellClick(habit, date)}
                              aria-label={`${done ? 'Unlog' : 'Log'} "${habit.name}" for ${date.toLocaleDateString()}`}
                              className={cn(
                                'h-5 w-5 rounded-full border transition-colors',
                                disabled
                                  ? 'border-transparent'
                                  : done
                                    ? 'border-success bg-success'
                                    : 'border-divider hover:border-accent hover:bg-accent-muted/40',
                              )}
                            />
                          </div>
                        )
                      })}
                    </div>
                  )
                })}
              </div>
            </div>
          </div>
        </div>
      )}

      {archived.length > 0 && (
        <section className="mt-6 shrink-0">
          <h2 className="mb-2 text-xs font-medium uppercase tracking-wide text-text-secondary">
            Archived — {archived.length}
          </h2>
          <ul className="flex flex-col gap-2">
            {archived.map((habit) => (
              <li
                key={habit.id}
                className="flex items-center gap-3 rounded-leo-md border border-divider bg-surface px-3 py-2 opacity-60"
              >
                <span className="flex-1 text-sm text-text-primary">{habit.name}</span>
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label={`Restore "${habit.name}"`}
                  onClick={() => void setHabitArchived(habit, false)}
                >
                  <ArchiveRestore className="h-4 w-4" />
                </Button>
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label={`Delete "${habit.name}"`}
                  className="text-text-secondary hover:text-danger"
                  onClick={() => void deleteHabit(habit, instancesByHabit.get(habit.id) ?? [])}
                >
                  <Trash2 className="h-4 w-4" />
                </Button>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  )
}
