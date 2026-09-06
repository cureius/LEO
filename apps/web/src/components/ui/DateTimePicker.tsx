import * as React from 'react'
import { CalendarIcon, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Calendar } from '@/components/ui/calendar'
import { TimeStepper } from '@/components/ui/TimeStepper'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { endOfDay } from '@/domain/dates'
import { cn } from '@/lib/utils'

interface DateTimePickerProps {
  /** ISO 8601 string, or '' when unset. */
  value: string
  /** Called with an ISO 8601 string, or '' when cleared. */
  onChange: (isoString: string) => void
  placeholder?: string
  className?: string
  id?: string
}

function combine(date: Date, timeStr: string): Date {
  const [hours, minutes] = timeStr.split(':').map(Number)
  const next = new Date(date)
  next.setHours(hours || 0, minutes || 0, 0, 0)
  return next
}

function toTimeInputValue(date: Date): string {
  return `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`
}

function inOneHour(): Date {
  const d = new Date()
  d.setMinutes(d.getMinutes() + 60, 0, 0)
  const remainder = d.getMinutes() % 15
  if (remainder !== 0) d.setMinutes(d.getMinutes() + (15 - remainder))
  return d
}
function tonight(): Date {
  const d = new Date()
  d.setHours(19, 0, 0, 0)
  return d
}
function tomorrowMorning(): Date {
  const d = new Date()
  d.setDate(d.getDate() + 1)
  d.setHours(9, 0, 0, 0)
  return d
}
function nextWeek(): Date {
  const d = new Date()
  d.setDate(d.getDate() + 7)
  d.setHours(9, 0, 0, 0)
  return d
}

const QUICK_PICKS: { label: string; get: () => Date }[] = [
  { label: 'In 1 hour', get: inOneHour },
  { label: 'Tonight', get: tonight },
  { label: 'Tomorrow', get: tomorrowMorning },
  { label: 'Next week', get: nextWeek },
  { label: 'End of day', get: () => endOfDay(new Date()) },
]

/**
 * Entirely replaces the previous Calendar+combobox-dropdown design — that
 * inner dropdown had no viewport awareness and stayed fragile even after
 * teaching it to flip (a floating list nested inside an already-floating
 * Popover). This version has one floating surface, not two: quick-pick
 * presets for the common cases (one click, no calendar/time fiddling at
 * all), a calendar for picking a specific date, and TimeStepper's inline
 * click/scroll/type controls for time — nothing else in the tree floats or
 * needs its own collision handling.
 */
export function DateTimePicker({ value, onChange, placeholder = 'Pick date & time', className, id }: DateTimePickerProps) {
  const selected = value ? new Date(value) : undefined
  const [open, setOpen] = React.useState(false)
  // Defaults to the current time, not a fixed hour, so a freshly opened
  // picker already reflects "now" rather than an arbitrary 9am.
  const [pendingTime, setPendingTime] = React.useState(() => toTimeInputValue(selected ?? new Date()))

  React.useEffect(() => {
    if (selected) setPendingTime(toTimeInputValue(selected))
  }, [value])

  function handleSelectDate(date: Date | undefined) {
    if (!date) return
    onChange(combine(date, pendingTime).toISOString())
  }

  function handleTimeChange(time: string) {
    setPendingTime(time)
    if (selected) onChange(combine(selected, time).toISOString())
  }

  function handleQuickPick(date: Date) {
    onChange(date.toISOString())
    setOpen(false)
  }

  function handleClear(e: React.MouseEvent) {
    e.stopPropagation()
    onChange('')
  }

  const label = selected
    ? selected.toLocaleString(undefined, {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
      })
    : placeholder

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          id={id}
          type="button"
          variant="outline"
          className={cn('w-full justify-start gap-2 font-normal', !selected && 'text-muted-foreground', className)}
        >
          <CalendarIcon className="h-4 w-4 shrink-0 opacity-60" />
          <span className="flex-1 truncate text-left">{label}</span>
          {selected && (
            <X
              className="h-3.5 w-3.5 shrink-0 opacity-60 hover:opacity-100"
              onClick={handleClear}
              role="button"
              aria-label="Clear date"
            />
          )}
        </Button>
      </PopoverTrigger>
      {/* collisionPadding + the max-w backstop: this popover could otherwise
          render partially off-screen on narrower viewports — Radix's own
          collision avoidance flips/shifts it but doesn't guarantee it never
          touches the edge, and w-auto alone has no hard ceiling. */}
      <PopoverContent className="w-auto max-w-[calc(100vw-1.5rem)] overflow-x-auto p-3" align="start" collisionPadding={12}>
        <div className="mb-3 flex flex-wrap gap-1.5">
          {QUICK_PICKS.map((pick) => (
            <button
              key={pick.label}
              type="button"
              onClick={() => handleQuickPick(pick.get())}
              className="rounded-leo-pill bg-surface-elevated px-2.5 py-1 text-xs font-medium text-text-primary hover:bg-accent-muted"
            >
              {pick.label}
            </button>
          ))}
        </div>

        <Calendar mode="single" selected={selected} onSelect={handleSelectDate} autoFocus />

        <div className="mt-2 flex items-center justify-between gap-2 border-t border-divider pt-2">
          <span className="text-sm text-text-secondary">Time</span>
          <TimeStepper value={pendingTime} onChange={handleTimeChange} />
        </div>

        <Button type="button" size="sm" className="mt-3 w-full" onClick={() => setOpen(false)} disabled={!selected}>
          Done
        </Button>
      </PopoverContent>
    </Popover>
  )
}
