import * as React from 'react'
import { ChevronDown, ChevronLeft, ChevronRight } from 'lucide-react'
import type { DayButton } from 'react-day-picker'
import { Button } from '@/components/ui/button'
import { Calendar } from '@/components/ui/calendar'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { cn } from '@/lib/utils'
import type { DomainItem } from '@/domain/types'

const DAY_MS = 86_400_000
const WEEKDAY_LABELS = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']
type ViewMode = 'week' | 'month' | 'quarter' | 'year'
const VIEW_MODES: { mode: ViewMode; label: string }[] = [
  { mode: 'week', label: 'Week' },
  { mode: 'month', label: 'Month' },
  { mode: 'quarter', label: 'Quarter' },
  { mode: 'year', label: 'Year' },
]

function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}
function quarterStartMonth(d: Date): number {
  return Math.floor(d.getMonth() / 3) * 3
}
function countFor(itemsByDay: Map<string, DomainItem[]>, day: Date): number {
  return itemsByDay.get(day.toDateString())?.length ?? 0
}

/**
 * Compact calendar day button used by the Quarter/Year panels — a plain
 * number + density dot. These stay dot-only (not titles) because Quarter
 * tiles 3 months and Year tiles 12 — there's no room for text there, only
 * "does this day have anything on it."
 */
function makeDensityDayButton(itemsByDay: Map<string, DomainItem[]>) {
  function DensityDayButton({ className, day, modifiers, ...props }: React.ComponentProps<typeof DayButton>) {
    const count = countFor(itemsByDay, day.date)
    return (
      <button
        type="button"
        className={cn(
          'relative flex aspect-square size-auto w-full flex-col items-center justify-center gap-0.5 rounded-md text-xs font-normal transition-colors hover:bg-surface-elevated',
          modifiers.today && !modifiers.selected && 'bg-accent-muted font-semibold text-accent',
          modifiers.selected && 'bg-primary font-semibold text-primary-foreground hover:bg-primary/90',
          modifiers.outside && 'text-muted-foreground opacity-40',
          className
        )}
        {...props}
      >
        <span>{day.date.getDate()}</span>
        <span className={cn('h-1 w-1 rounded-full', count > 0 ? (modifiers.selected ? 'bg-white/85' : 'bg-accent') : 'bg-transparent')} />
      </button>
    )
  }
  return DensityDayButton
}

function MonthsGrid({
  anchor,
  numberOfMonths,
  cellSize,
  selectedDate,
  onSelectDate,
  itemsByDay,
}: {
  anchor: Date
  numberOfMonths: number
  cellSize: string
  selectedDate: Date
  onSelectDate: (date: Date) => void
  itemsByDay: Map<string, DomainItem[]>
}) {
  const DensityDayButton = React.useMemo(() => makeDensityDayButton(itemsByDay), [itemsByDay])
  return (
    <Calendar
      key={`${anchor.getFullYear()}-${anchor.getMonth()}-${numberOfMonths}`}
      mode="single"
      month={anchor}
      numberOfMonths={numberOfMonths}
      hideNavigation
      selected={selectedDate}
      onSelect={(date) => date && onSelectDate(date)}
      components={{ DayButton: DensityDayButton }}
      className="w-full"
      style={{ ['--cell-size' as string]: cellSize }}
      classNames={{ months: 'grid grid-cols-3 gap-x-6 gap-y-4', month: 'w-full' }}
    />
  )
}

/**
 * Full-width month grid with inline item-title previews per day — the
 * Google/Apple Calendar "month view" pattern. Deliberately NOT built on
 * react-day-picker like the Quarter/Year panels: those only need a bare
 * number + dot, but a proper month view needs each cell to hold a small
 * list of titles, which react-day-picker's day-button slot isn't shaped
 * for. A plain CSS grid is simpler and gives full control over cell
 * content and height.
 */
function MonthGrid({
  anchor,
  selectedDate,
  onSelectDate,
  itemsByDay,
}: {
  anchor: Date
  selectedDate: Date
  onSelectDate: (date: Date) => void
  itemsByDay: Map<string, DomainItem[]>
}) {
  const MAX_VISIBLE = 3
  const today = startOfDay(new Date())
  const monthStart = new Date(anchor.getFullYear(), anchor.getMonth(), 1)
  const monthEnd = new Date(anchor.getFullYear(), anchor.getMonth() + 1, 0)
  const gridStart = new Date(monthStart.getTime() - ((monthStart.getDay() + 6) % 7) * DAY_MS)
  const trailingDays = (7 - (((monthEnd.getDay() + 6) % 7) + 1)) % 7
  const gridEnd = new Date(monthEnd.getTime() + trailingDays * DAY_MS)
  const totalDays = Math.round((gridEnd.getTime() - gridStart.getTime()) / DAY_MS) + 1
  const days = Array.from({ length: totalDays }, (_, i) => new Date(gridStart.getTime() + i * DAY_MS))

  return (
    <div className="overflow-hidden rounded-leo-md border border-divider">
      <div className="grid grid-cols-7 border-b border-divider bg-surface-elevated">
        {WEEKDAY_LABELS.map((label) => (
          <div key={label} className="px-2 py-1.5 text-center text-[10px] font-semibold tracking-wide text-text-secondary uppercase">
            {label}
          </div>
        ))}
      </div>
      <div className="grid grid-cols-7 gap-px bg-divider">
        {days.map((day) => {
          const key = day.toDateString()
          const dayItems = itemsByDay.get(key) ?? []
          const isOutside = day.getMonth() !== anchor.getMonth()
          const isToday = day.getTime() === today.getTime()
          const isSelected = key === selectedDate.toDateString()
          const visible = dayItems.slice(0, MAX_VISIBLE)
          const overflow = dayItems.length - visible.length

          return (
            <button
              key={key}
              type="button"
              onClick={() => onSelectDate(day)}
              aria-label={`${day.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' })}${dayItems.length ? `, ${dayItems.length} items` : ''}`}
              aria-pressed={isSelected}
              className={cn(
                'flex min-h-[92px] flex-col items-stretch gap-1 bg-surface p-1.5 text-left transition-colors hover:bg-surface-elevated focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring/50',
                isOutside && 'bg-background/60'
              )}
            >
              <span
                className={cn(
                  'flex h-5 w-5 items-center justify-center rounded-full text-xs font-semibold',
                  isSelected
                    ? 'bg-accent text-white'
                    : isToday
                      ? 'bg-accent-muted text-accent'
                      : isOutside
                        ? 'text-text-secondary/50'
                        : 'text-text-primary'
                )}
              >
                {day.getDate()}
              </span>
              <div className="flex flex-col gap-0.5">
                {visible.map((item) => (
                  <span
                    key={item.id}
                    className={cn(
                      'truncate rounded-leo-sm px-1 py-0.5 text-left text-[10px] font-medium',
                      item.importance === 3 ? 'bg-danger/15 text-danger' : 'bg-accent-muted text-text-primary'
                    )}
                  >
                    {item.title}
                  </span>
                ))}
                {overflow > 0 && <span className="px-1 text-[10px] font-medium text-text-secondary">+{overflow} more</span>}
              </div>
            </button>
          )
        })}
      </div>
    </div>
  )
}

/**
 * Date navigator for Today — a week strip by default, with Month/Quarter/
 * Year zoom levels for broader browsing. Native only ever needed a week
 * (it's a phone), but the web build has the screen space for more, and
 * jumping 3 months out used to mean dozens of arrow clicks.
 *
 * `selectedDate` (which day's items show below) and `viewAnchor` (which
 * month/quarter/year is currently displayed) are deliberately separate:
 * paging through months to look around shouldn't yank the day list out
 * from under you until you actually click a day.
 */
export function DateNavigator({
  selectedDate,
  onSelectDate,
  itemsByDay,
}: {
  selectedDate: Date
  onSelectDate: (date: Date) => void
  itemsByDay: Map<string, DomainItem[]>
}) {
  const [viewMode, setViewMode] = React.useState<ViewMode>('week')
  const [viewAnchor, setViewAnchor] = React.useState(selectedDate)
  const [jumpOpen, setJumpOpen] = React.useState(false)
  const dayRefs = React.useRef(new Map<string, HTMLButtonElement>())

  const today = new Date()
  const startOfToday = startOfDay(today)
  const viewingToday = selectedDate.getTime() === startOfToday.getTime()

  function focusDay(date: Date) {
    requestAnimationFrame(() => dayRefs.current.get(date.toDateString())?.focus())
  }

  function pickDate(date: Date) {
    onSelectDate(date)
    setViewAnchor(date)
  }

  function switchMode(mode: ViewMode) {
    setViewAnchor(selectedDate)
    setViewMode(mode)
  }

  function goToday() {
    pickDate(startOfToday)
    if (viewMode === 'week') focusDay(startOfToday)
  }

  function navigate(delta: number) {
    if (viewMode === 'week') {
      const next = new Date(selectedDate.getTime() + delta * 7 * DAY_MS)
      onSelectDate(next)
      setViewAnchor(next)
      focusDay(next)
      return
    }
    if (viewMode === 'month') {
      setViewAnchor(new Date(viewAnchor.getFullYear(), viewAnchor.getMonth() + delta, 1))
    } else if (viewMode === 'quarter') {
      setViewAnchor(new Date(viewAnchor.getFullYear(), quarterStartMonth(viewAnchor) + delta * 3, 1))
    } else {
      setViewAnchor(new Date(viewAnchor.getFullYear() + delta, 0, 1))
    }
  }

  // Week panel geometry (kept from the original strip).
  const mondayOffset = (selectedDate.getDay() + 6) % 7
  const weekStart = new Date(selectedDate.getTime() - mondayOffset * DAY_MS)
  const weekDays = Array.from({ length: 7 }, (_, i) => new Date(weekStart.getTime() + i * DAY_MS))

  function handleDayKeyDown(e: React.KeyboardEvent, day: Date) {
    const moves: Record<string, number> = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }
    let next: Date | null = null
    if (e.key in moves) next = new Date(day.getTime() + moves[e.key] * DAY_MS)
    else if (e.key === 'Home') next = startOfToday
    if (!next) return
    e.preventDefault()
    pickDate(next)
    focusDay(next)
  }

  const periodLabel =
    viewMode === 'week'
      ? weekStart.toLocaleDateString(undefined, { month: 'long', year: 'numeric' })
      : viewMode === 'month'
        ? viewAnchor.toLocaleDateString(undefined, { month: 'long', year: 'numeric' })
        : viewMode === 'quarter'
          ? `Q${Math.floor(viewAnchor.getMonth() / 3) + 1} ${viewAnchor.getFullYear()}`
          : `${viewAnchor.getFullYear()}`

  return (
    <div className="mb-4">
      <div className="mb-2 flex items-center gap-1">
        <Button variant="ghost" size="icon" aria-label={`Previous ${viewMode}`} onClick={() => navigate(-1)}>
          <ChevronLeft className="h-4 w-4" />
        </Button>

        <Popover open={jumpOpen} onOpenChange={setJumpOpen}>
          <PopoverTrigger asChild>
            <button
              type="button"
              className="flex flex-1 items-center justify-center gap-1 rounded-leo-sm py-1 text-sm font-semibold text-text-primary hover:bg-surface-elevated"
            >
              {periodLabel}
              <ChevronDown className="h-3.5 w-3.5 opacity-60" />
            </button>
          </PopoverTrigger>
          <PopoverContent className="w-auto p-3" align="center">
            <Calendar
              mode="single"
              selected={selectedDate}
              defaultMonth={selectedDate}
              onSelect={(date) => {
                if (!date) return
                pickDate(date)
                setJumpOpen(false)
                if (viewMode === 'week') focusDay(date)
              }}
              autoFocus
            />
          </PopoverContent>
        </Popover>

        <Button variant="ghost" size="icon" aria-label={`Next ${viewMode}`} onClick={() => navigate(1)}>
          <ChevronRight className="h-4 w-4" />
        </Button>
        {!viewingToday && (
          <Button size="sm" variant="secondary" onClick={goToday}>
            Today
          </Button>
        )}
      </div>

      <div className="mb-3 flex gap-1 rounded-leo-md bg-surface-elevated p-1">
        {VIEW_MODES.map(({ mode, label }) => (
          <button
            key={mode}
            type="button"
            onClick={() => switchMode(mode)}
            aria-pressed={viewMode === mode}
            className={cn(
              'flex-1 rounded-leo-sm py-1 text-xs font-medium transition-colors',
              viewMode === mode ? 'bg-surface text-text-primary shadow-sm' : 'text-text-secondary hover:text-text-primary'
            )}
          >
            {label}
          </button>
        ))}
      </div>

      {viewMode === 'week' && (
        <div role="grid" aria-label="Select a day" className="grid grid-cols-7 gap-1">
          {weekDays.map((day) => {
            const count = countFor(itemsByDay, day)
            const selected = day.toDateString() === selectedDate.toDateString()
            const today_ = day.getTime() === startOfToday.getTime()
            return (
              <button
                key={day.toISOString()}
                ref={(el) => {
                  if (el) dayRefs.current.set(day.toDateString(), el)
                  else dayRefs.current.delete(day.toDateString())
                }}
                type="button"
                role="gridcell"
                tabIndex={selected ? 0 : -1}
                onClick={() => pickDate(day)}
                onKeyDown={(e) => handleDayKeyDown(e, day)}
                aria-label={`${day.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' })}${count > 0 ? `, ${count} items` : ''}`}
                aria-pressed={selected}
                className={cn(
                  'flex flex-col items-center gap-1 rounded-leo-lg py-2 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50',
                  selected
                    ? 'bg-accent text-white'
                    : today_
                      ? 'bg-accent-muted text-accent'
                      : 'text-text-primary hover:bg-surface-elevated'
                )}
              >
                <span className="text-[10px] font-semibold uppercase tracking-wide opacity-80">
                  {day.toLocaleDateString(undefined, { weekday: 'narrow' })}
                </span>
                <span className="text-base font-bold">{day.getDate()}</span>
                <span className="flex h-1 gap-0.5">
                  {Array.from({ length: Math.min(count, 3) }).map((_, i) => (
                    <span key={i} className={`h-1 w-1 rounded-full ${selected ? 'bg-white/85' : 'bg-accent'}`} />
                  ))}
                </span>
              </button>
            )
          })}
        </div>
      )}

      {viewMode === 'month' && (
        <MonthGrid
          anchor={new Date(viewAnchor.getFullYear(), viewAnchor.getMonth(), 1)}
          selectedDate={selectedDate}
          onSelectDate={pickDate}
          itemsByDay={itemsByDay}
        />
      )}

      {viewMode === 'quarter' && (
        <MonthsGrid
          anchor={new Date(viewAnchor.getFullYear(), quarterStartMonth(viewAnchor), 1)}
          numberOfMonths={3}
          cellSize="1.75rem"
          selectedDate={selectedDate}
          onSelectDate={pickDate}
          itemsByDay={itemsByDay}
        />
      )}

      {viewMode === 'year' && (
        <MonthsGrid
          anchor={new Date(viewAnchor.getFullYear(), 0, 1)}
          numberOfMonths={12}
          cellSize="1.4rem"
          selectedDate={selectedDate}
          onSelectDate={pickDate}
          itemsByDay={itemsByDay}
        />
      )}
    </div>
  )
}
