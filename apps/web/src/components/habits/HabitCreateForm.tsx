import { useState, type FormEvent } from 'react'
import { Button } from '@/components/ui/button'
import { TextField } from '@/components/ui/TextField'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { addHabit } from '@/sync/mutations'
import type { Habit, HabitFrequency, Weekday } from '@/domain/types'

// This form only ever offers these 3 hints — 'specific' (hour/minute) needs
// a richer picker UI, deliberately out of scope for v1's habit creation flow.
type SimpleTimeHint = 'morning' | 'afternoon' | 'evening'

const WEEKDAYS: { value: Weekday; label: string }[] = [
  { value: 'MO', label: 'Mon' },
  { value: 'TU', label: 'Tue' },
  { value: 'WE', label: 'Wed' },
  { value: 'TH', label: 'Thu' },
  { value: 'FR', label: 'Fri' },
  { value: 'SA', label: 'Sat' },
  { value: 'SU', label: 'Sun' },
]

function ruleForFrequency(frequency: HabitFrequency): string {
  switch (frequency.type) {
    case 'daily':
      return 'FREQ=DAILY'
    case 'specificDays':
      return `FREQ=WEEKLY;BYDAY=${frequency.days.join(',')}`
    case 'timesPerWeek':
      return 'FREQ=WEEKLY' // count-based habits aren't day-scheduled; materializer still needs a valid rule
    case 'custom':
      return frequency.rule.raw
  }
}

export function HabitCreateForm() {
  const [name, setName] = useState('')
  const [mode, setMode] = useState<'daily' | 'specificDays'>('daily')
  const [selectedDays, setSelectedDays] = useState<Set<Weekday>>(new Set(['MO', 'WE', 'FR']))
  const [timeHint, setTimeHint] = useState<SimpleTimeHint>('morning')

  function toggleDay(day: Weekday) {
    setSelectedDays((prev) => {
      const next = new Set(prev)
      if (next.has(day)) next.delete(day)
      else next.add(day)
      return next
    })
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    const trimmed = name.trim()
    if (!trimmed) return
    if (mode === 'specificDays' && selectedDays.size === 0) return

    const frequency: HabitFrequency =
      mode === 'daily' ? { type: 'daily' } : { type: 'specificDays', days: Array.from(selectedDays) }

    const habit: Habit = {
      id: crypto.randomUUID(),
      name: trimmed,
      frequency,
      timeHint: { type: timeHint },
      forgiveness: { type: 'none' },
      recurrenceRuleRaw: ruleForFrequency(frequency),
      createdAt: new Date(),
      isArchived: false,
    }
    void addHabit(habit)
    setName('')
  }

  return (
    <form onSubmit={handleSubmit} className="mb-6 flex flex-col gap-3 rounded-leo-md border border-divider bg-surface p-3">
      <TextField label="Habit name" placeholder="Morning run" value={name} onChange={(e) => setName(e.target.value)} />

      <div className="flex flex-col gap-1.5">
        <span className="text-sm font-medium text-text-primary">Frequency</span>
        <div className="flex gap-2">
          <Button type="button" variant={mode === 'daily' ? 'default' : 'secondary'} size="sm" onClick={() => setMode('daily')}>
            Every day
          </Button>
          <Button
            type="button"
            variant={mode === 'specificDays' ? 'default' : 'secondary'}
            size="sm"
            onClick={() => setMode('specificDays')}
          >
            Specific days
          </Button>
        </div>
        {mode === 'specificDays' && (
          <div className="mt-1 flex flex-wrap gap-1">
            {WEEKDAYS.map(({ value, label }) => (
              <button
                key={value}
                type="button"
                aria-pressed={selectedDays.has(value)}
                onClick={() => toggleDay(value)}
                className={`rounded-leo-pill px-2.5 py-1 text-xs ${
                  selectedDays.has(value) ? 'bg-accent text-white' : 'bg-surface-elevated text-text-secondary'
                }`}
              >
                {label}
              </button>
            ))}
          </div>
        )}
      </div>

      <div className="flex flex-col gap-1.5">
        <Label htmlFor="time-hint">Time of day</Label>
        <Select value={timeHint} onValueChange={(value) => setTimeHint(value as SimpleTimeHint)}>
          <SelectTrigger id="time-hint" className="w-full">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="morning">Morning</SelectItem>
            <SelectItem value="afternoon">Afternoon</SelectItem>
            <SelectItem value="evening">Evening</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <Button type="submit" className="self-start">
        Create habit
      </Button>
    </form>
  )
}
