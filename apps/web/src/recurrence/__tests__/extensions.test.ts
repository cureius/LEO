import { describe, expect, it } from 'vitest'
import { applyExtensions } from '../extensions'

describe('applyExtensions', () => {
  it('workdaysOnly filters out Saturday and Sunday', () => {
    // Mon Jul 6 - Sun Jul 12, 2026 — one full week.
    const week = [6, 7, 8, 9, 10, 11, 12].map((d) => new Date(2026, 6, d))
    const result = applyExtensions(week, ['workdaysOnly'])
    expect(result.map((d) => d.getDate())).toEqual([6, 7, 8, 9, 10]) // Mon-Fri only
  })

  it('skipUSHolidays filters out a known federal holiday', () => {
    const dates = [new Date(2026, 6, 3), new Date(2026, 6, 6)] // observed July 4th + an ordinary day
    const result = applyExtensions(dates, ['skipUSHolidays'])
    expect(result).toHaveLength(1)
    expect(result[0].getDate()).toBe(6)
  })

  it('firstWeekdayOfMonth WALKS a weekend/holiday date FORWARD rather than dropping it — a map, not a filter', () => {
    // Confirmed from RecurrenceEngine.swift source: this extension transforms
    // each date rather than removing it. A Saturday should roll to the
    // following Monday (or later, if that Monday is also a holiday).
    const saturday = new Date(2026, 6, 4) // Sat Jul 4 (also the observed holiday is Jul 3, a Friday)
    const result = applyExtensions([saturday], ['firstWeekdayOfMonth'])
    expect(result).toHaveLength(1) // never dropped
    expect(result[0].getDay()).not.toBe(0)
    expect(result[0].getDay()).not.toBe(6)
  })

  it('applies multiple extensions in array order, each stage feeding the next', () => {
    const dates = [
      new Date(2026, 6, 3), // Fri, observed July 4th holiday
      new Date(2026, 6, 4), // Sat
      new Date(2026, 6, 6), // Mon, ordinary
    ]
    const result = applyExtensions(dates, ['workdaysOnly', 'skipUSHolidays'])
    expect(result.map((d) => d.getDate())).toEqual([6]) // Fri dropped by holiday, Sat by weekend
  })

  it('is a no-op with an empty extensions array', () => {
    const dates = [new Date(2026, 6, 4), new Date(2026, 6, 5)]
    expect(applyExtensions(dates, [])).toEqual(dates)
  })
})
