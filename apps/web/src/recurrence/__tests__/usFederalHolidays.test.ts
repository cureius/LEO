import { describe, expect, it } from 'vitest'
import { isUSFederalHoliday, usFederalHolidays } from '../usFederalHolidays'

describe('usFederalHolidays — observed-date shifting', () => {
  it('shifts a Saturday holiday to the preceding Friday (July 4, 2026 is a Saturday)', () => {
    // Independently verified: new Date(2026,6,4).getDay() === 6 (Saturday).
    const holidays = usFederalHolidays(2026)
    const independenceDay = holidays.find((d) => d.getMonth() === 6)!
    expect(independenceDay.getDate()).toBe(3)
  })

  it('does not shift a holiday that already falls on a weekday (Dec 25, 2026 is a Friday)', () => {
    const holidays = usFederalHolidays(2026)
    const christmas = holidays.find((d) => d.getMonth() === 11 && d.getDate() >= 20)!
    expect(christmas.getDate()).toBe(25)
  })

  it('computes MLK Day as the 3rd Monday of January (2026 -> Jan 19)', () => {
    const holidays = usFederalHolidays(2026)
    // Jan 1 is a fixed New Year's holiday too; MLK is the other January entry.
    const januaryHolidays = holidays.filter((d) => d.getMonth() === 0)
    expect(januaryHolidays.map((d) => d.getDate()).sort((a, b) => a - b)).toEqual([1, 19])
  })

  it('computes Memorial Day as the last Monday of May (2026 -> May 25)', () => {
    const holidays = usFederalHolidays(2026)
    const memorialDay = holidays.find((d) => d.getMonth() === 4)!
    expect(memorialDay.getDate()).toBe(25)
  })

  it('computes Thanksgiving as the 4th Thursday of November (2026 -> Nov 26)', () => {
    const holidays = usFederalHolidays(2026)
    const thanksgiving = holidays.find((d) => d.getMonth() === 10 && d.getDate() > 15)!
    expect(thanksgiving.getDate()).toBe(26)
  })

  it('returns exactly 11 holidays per year, matching the native list', () => {
    expect(usFederalHolidays(2026)).toHaveLength(11)
  })
})

describe('isUSFederalHoliday', () => {
  it('is true for the observed Independence Day date', () => {
    expect(isUSFederalHoliday(new Date(2026, 6, 3))).toBe(true)
  })
  it('is false for an ordinary day', () => {
    expect(isUSFederalHoliday(new Date(2026, 6, 15))).toBe(false)
  })
})
