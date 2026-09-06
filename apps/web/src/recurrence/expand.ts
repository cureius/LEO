import { rrulestr } from 'rrule'
import { applyExtensions } from './extensions'
import type { RecurrenceRule } from '@/domain/types'

/**
 * `rrule` computes BYDAY/weekday arithmetic using the Date object's UTC
 * getters internally, not local time (a documented rrule.js behavior — it
 * has no timezone support of its own). LEO's habit anchors are *floating*
 * wall-clock time (Swift's `Calendar.current`, no explicit timezone), so
 * feeding it a real local Date silently shifts every BYDAY-based rule by
 * whatever the local UTC offset happens to be — caught live in a non-UTC
 * timezone (IST, UTC+5:30): `FREQ=WEEKLY;BYDAY=MO,WE,FR` anchored on a local
 * Wednesday came back as Thu/Sat/Tue, a systematic +1-day shift, not
 * Mon/Wed/Fri. The standard workaround: construct a Date whose *UTC* clock
 * fields equal the intended *local* wall-clock fields before handing it to
 * rrule, then read the result back via the UTC getters. This makes rrule's
 * UTC-based arithmetic operate on the numbers we actually mean, regardless
 * of which timezone this code happens to run in.
 */
function toFloatingUTC(date: Date): Date {
  return new Date(
    Date.UTC(date.getFullYear(), date.getMonth(), date.getDate(), date.getHours(), date.getMinutes(), date.getSeconds()),
  )
}

function fromFloatingUTC(date: Date): Date {
  return new Date(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(), date.getUTCHours(), date.getUTCMinutes(), date.getUTCSeconds())
}

/**
 * Occurrence dates for `rule` starting at `anchorStart`, within the closed
 * interval [windowStart, windowEnd] (both ends inclusive — matches Swift's
 * `DateInterval.contains`, ported here as `rrule`'s `.between(..., inc=true)`).
 *
 * Standard RFC5545 expansion (FREQ/INTERVAL/BYDAY/COUNT/UNTIL/etc.) is
 * delegated to the `rrule` package rather than hand-ported from
 * RecurrenceEngine.swift's ~250-line custom expander — RRULE has a long
 * tail of edge cases (DST, BYSETPOS, leap years) that a battle-tested
 * library has already been debugged against; re-deriving that logic fresh
 * would be pure risk with no product benefit. Only LEO's own 3 invented
 * extensions (workdaysOnly/skipUSHolidays/firstWeekdayOfMonth) are hand-ported,
 * in extensions.ts, since no library covers LEO-specific behavior.
 */
export function occurrences(rule: RecurrenceRule, anchorStart: Date, windowStart: Date, windowEnd: Date): Date[] {
  const parsed = rrulestr(rule.raw, { dtstart: toFloatingUTC(anchorStart) })
  const rawFloating = parsed.between(toFloatingUTC(windowStart), toFloatingUTC(windowEnd), true)
  const raw = rawFloating.map(fromFloatingUTC)
  const filtered = applyExtensions(raw, rule.extensions)
  return filtered.slice().sort((a, b) => a.getTime() - b.getTime())
}
