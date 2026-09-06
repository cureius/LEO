/**
 * Port of LEO/Domain/Recurrence/USFederalHolidays.swift — a rule-based
 * computation (nth-weekday-of-month, last-weekday-of-month, Sat/Sun
 * observed-date shifting), not a hardcoded date table, so it's correct for
 * any year rather than needing manual upkeep. Used by the `skipUSHolidays`
 * LEORuleExtension filter in extensions.ts.
 *
 * "Observed" rule (matches Swift exactly): a holiday landing on Saturday is
 * observed the preceding Friday; on Sunday, the following Monday.
 */

function dateFrom(year: number, month: number, day: number): Date {
  // Local time, day-precision only — matches Calendar.current usage in the
  // Swift original; RRULE expansion elsewhere in this module also operates
  // in local time, so this stays consistent with the rest of the engine.
  return new Date(year, month - 1, day)
}

function isSameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

/** Fixed-date holiday adjusted to the observed weekday — port of `observed()`. */
function observed(month: number, day: number, year: number): Date {
  const date = dateFrom(year, month, day)
  const weekday = date.getDay() // 0=Sun … 6=Sat
  if (weekday === 6) return new Date(date.getTime() - 86400_000) // Saturday -> Friday
  if (weekday === 0) return new Date(date.getTime() + 86400_000) // Sunday -> Monday
  return date
}

/** Nth occurrence of a weekday within a month (1-based) — port of `nthWeekday()`. */
function nthWeekday(weekday: number, n: number, month: number, year: number): Date {
  const firstOfMonth = dateFrom(year, month, 1)
  const firstWD = firstOfMonth.getDay()
  let offset = weekday - firstWD
  if (offset < 0) offset += 7
  offset += (n - 1) * 7
  return new Date(firstOfMonth.getTime() + offset * 86400_000)
}

/** Last occurrence of a weekday within a month — port of `lastWeekday()`. */
function lastWeekdayOfMonth(weekday: number, month: number, year: number): Date {
  const firstOfNext = month === 12 ? dateFrom(year + 1, 1, 1) : dateFrom(year, month + 1, 1)
  const lastOfMonth = new Date(firstOfNext.getTime() - 86400_000)
  const lastWD = lastOfMonth.getDay()
  let offset = weekday - lastWD
  if (offset > 0) offset -= 7
  return new Date(lastOfMonth.getTime() + offset * 86400_000)
}

const MONDAY = 1
const THURSDAY = 4

/** All 11 federal holidays (observed dates) for a given year — port of `holidays(for:)`. */
export function usFederalHolidays(year: number): Date[] {
  return [
    observed(1, 1, year), // New Year's Day
    nthWeekday(MONDAY, 3, 1, year), // MLK Day — 3rd Monday of January
    nthWeekday(MONDAY, 3, 2, year), // Presidents' Day — 3rd Monday of February
    lastWeekdayOfMonth(MONDAY, 5, year), // Memorial Day — last Monday of May
    observed(6, 19, year), // Juneteenth
    observed(7, 4, year), // Independence Day
    nthWeekday(MONDAY, 1, 9, year), // Labor Day — 1st Monday of September
    nthWeekday(MONDAY, 2, 10, year), // Columbus Day — 2nd Monday of October
    observed(11, 11, year), // Veterans Day
    nthWeekday(THURSDAY, 4, 11, year), // Thanksgiving — 4th Thursday of November
    observed(12, 25, year), // Christmas Day
  ]
}

export function isUSFederalHoliday(date: Date): boolean {
  return usFederalHolidays(date.getFullYear()).some((h) => isSameDay(h, date))
}
