import { describe, expect, it } from 'vitest'
import { occurrences } from '../expand'

describe('occurrences — RFC5545 expansion via the rrule package', () => {
  it('FREQ=DAILY produces one occurrence per day within the window', () => {
    const anchor = new Date(2026, 6, 1) // Wed Jul 1, 2026
    const result = occurrences({ raw: 'FREQ=DAILY', extensions: [] }, anchor, new Date(2026, 6, 1), new Date(2026, 6, 5))
    expect(result.map((d) => d.getDate())).toEqual([1, 2, 3, 4, 5])
  })

  it('FREQ=WEEKLY;BYDAY=MO,WE,FR produces only those weekdays', () => {
    const anchor = new Date(2026, 6, 1) // a Wednesday
    const result = occurrences(
      { raw: 'FREQ=WEEKLY;BYDAY=MO,WE,FR', extensions: [] },
      anchor,
      new Date(2026, 6, 1),
      new Date(2026, 6, 12),
    )
    const weekdays = result.map((d) => d.getDay())
    expect(weekdays.every((wd) => wd === 1 || wd === 3 || wd === 5)).toBe(true)
  })

  it('respects COUNT — stops after the specified number of occurrences even if the window is wider', () => {
    const anchor = new Date(2026, 6, 1)
    const result = occurrences({ raw: 'FREQ=DAILY;COUNT=3', extensions: [] }, anchor, new Date(2026, 6, 1), new Date(2026, 6, 30))
    expect(result).toHaveLength(3)
  })

  it('respects UNTIL — no occurrences past the cutoff', () => {
    const anchor = new Date(2026, 6, 1)
    const result = occurrences(
      { raw: 'FREQ=DAILY;UNTIL=20260703T235959Z', extensions: [] },
      anchor,
      new Date(2026, 6, 1),
      new Date(2026, 6, 30),
    )
    expect(result.length).toBeLessThanOrEqual(4) // Jul 1-3 (+/-1 for TZ edge)
  })

  it('window bounds are inclusive on both ends (matches Swift DateInterval.contains)', () => {
    const anchor = new Date(2026, 6, 1)
    const result = occurrences({ raw: 'FREQ=DAILY', extensions: [] }, anchor, new Date(2026, 6, 1), new Date(2026, 6, 1))
    expect(result).toHaveLength(1) // the single-day window itself is a valid occurrence
  })

  it('applies LEO extensions after RFC5545 expansion (workdaysOnly on a daily rule -> weekdays only)', () => {
    const anchor = new Date(2026, 6, 1) // Wed
    const result = occurrences(
      { raw: 'FREQ=DAILY', extensions: ['workdaysOnly'] },
      anchor,
      new Date(2026, 6, 1),
      new Date(2026, 6, 12),
    )
    expect(result.every((d) => d.getDay() !== 0 && d.getDay() !== 6)).toBe(true)
  })

  it('results are sorted ascending', () => {
    const anchor = new Date(2026, 6, 1)
    const result = occurrences({ raw: 'FREQ=DAILY', extensions: [] }, anchor, new Date(2026, 6, 1), new Date(2026, 6, 10))
    const times = result.map((d) => d.getTime())
    expect(times).toEqual([...times].sort((a, b) => a - b))
  })
})
