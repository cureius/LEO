import { useState } from 'react'
import { ChevronDown, ChevronUp } from 'lucide-react'
import { cn } from '@/lib/utils'

interface TimeStepperProps {
  /** 24h "HH:mm". */
  value: string
  onChange: (value: string) => void
  className?: string
}

function parse(hhmm: string): { h24: number; m: number } {
  const [h, m] = hhmm.split(':').map(Number)
  return { h24: Number.isFinite(h) ? h : 0, m: Number.isFinite(m) ? m : 0 }
}

function toHHMM(h24: number, m: number): string {
  const wrappedH = ((h24 % 24) + 24) % 24
  const wrappedM = ((m % 60) + 60) % 60
  return `${String(wrappedH).padStart(2, '0')}:${String(wrappedM).padStart(2, '0')}`
}

/**
 * Replaces the old TimePicker's absolute-positioned suggestion dropdown
 * entirely — that dropdown had no viewport awareness (confirmed live: it
 * could render off the bottom of a short screen with no way to reach it),
 * and even after teaching it to flip upward, a floating list nested inside
 * an already-floating Popover was inherently fragile. This has no floating
 * element at all: hour, minute, and AM/PM live inline in the picker body,
 * each adjustable by click, scroll-wheel, or typing directly — nothing to
 * mis-position because nothing is positioned.
 */
export function TimeStepper({ value, onChange, className }: TimeStepperProps) {
  const { h24, m } = parse(value)
  const period = h24 < 12 ? 'AM' : 'PM'
  const h12 = h24 % 12 === 0 ? 12 : h24 % 12

  const [hourInput, setHourInput] = useState(String(h12))
  const [minuteInput, setMinuteInput] = useState(String(m).padStart(2, '0'))

  function setH12(next12: number, nextPeriod: 'AM' | 'PM') {
    const clamped = ((next12 - 1 + 12) % 12) + 1
    let next24 = clamped % 12
    if (nextPeriod === 'PM') next24 += 12
    onChange(toHHMM(next24, m))
  }

  function setMinute(nextM: number) {
    onChange(toHHMM(h24, nextM))
  }

  function commitHour(raw: string) {
    const n = parseInt(raw, 10)
    if (Number.isFinite(n) && n >= 1 && n <= 12) setH12(n, period)
    setHourInput(String(h12))
  }

  function commitMinute(raw: string) {
    const n = parseInt(raw, 10)
    if (Number.isFinite(n) && n >= 0 && n <= 59) setMinute(n)
    setMinuteInput(String(m).padStart(2, '0'))
  }

  return (
    <div className={cn('flex items-center gap-1.5', className)}>
      <Stepper
        value={hourInput}
        onValueChange={setHourInput}
        onCommit={commitHour}
        onStep={(dir) => setH12(h12 + dir, period)}
        aria-label="Hour"
      />
      <span className="text-lg font-medium text-text-secondary">:</span>
      <Stepper
        value={minuteInput}
        onValueChange={setMinuteInput}
        onCommit={commitMinute}
        onStep={(dir) => setMinute(m + dir)}
        aria-label="Minute"
      />
      <div className="ml-1 flex flex-col overflow-hidden rounded-leo-sm border border-divider">
        {(['AM', 'PM'] as const).map((p) => (
          <button
            key={p}
            type="button"
            onClick={() => setH12(h12, p)}
            aria-pressed={period === p}
            className={cn(
              'px-2 py-1 text-xs font-medium transition-colors',
              period === p ? 'bg-accent text-white' : 'bg-surface text-text-secondary hover:bg-surface-elevated',
            )}
          >
            {p}
          </button>
        ))}
      </div>
    </div>
  )
}

/** One scroll-wheel/click/type numeric field — the shared guts behind the
 *  hour and minute inputs above. Wheel-up increments, matching the "dial
 *  forward" feel of a physical scroll wheel turning a value up. */
function Stepper({
  value,
  onValueChange,
  onCommit,
  onStep,
  ['aria-label']: ariaLabel,
}: {
  value: string
  onValueChange: (v: string) => void
  onCommit: (v: string) => void
  onStep: (direction: 1 | -1) => void
  'aria-label': string
}) {
  return (
    <div className="flex flex-col items-center">
      <button type="button" onClick={() => onStep(1)} aria-label={`Increase ${ariaLabel}`} className="rounded-leo-sm p-0.5 text-text-secondary hover:bg-surface-elevated hover:text-text-primary">
        <ChevronUp className="h-3.5 w-3.5" />
      </button>
      <input
        value={value}
        onChange={(e) => onValueChange(e.target.value.replace(/[^0-9]/g, '').slice(0, 2))}
        onBlur={(e) => onCommit(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') e.currentTarget.blur()
          if (e.key === 'ArrowUp') {
            e.preventDefault()
            onStep(1)
          }
          if (e.key === 'ArrowDown') {
            e.preventDefault()
            onStep(-1)
          }
        }}
        onWheel={(e) => {
          e.preventDefault()
          onStep(e.deltaY < 0 ? 1 : -1)
        }}
        inputMode="numeric"
        aria-label={ariaLabel}
        className="w-9 rounded-leo-sm border border-divider bg-surface py-1 text-center text-base font-medium text-text-primary outline-none focus:border-accent"
      />
      <button type="button" onClick={() => onStep(-1)} aria-label={`Decrease ${ariaLabel}`} className="rounded-leo-sm p-0.5 text-text-secondary hover:bg-surface-elevated hover:text-text-primary">
        <ChevronDown className="h-3.5 w-3.5" />
      </button>
    </div>
  )
}
