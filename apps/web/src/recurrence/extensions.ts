import { isUSFederalHoliday } from './usFederalHolidays'
import type { LEORuleExtension } from '@/domain/types'

/**
 * Port of RecurrenceEngine.swift's applyExtensions/isWeekend/firstWeekdayIfNeeded
 * (lines 295-320). Applied in array order, each stage feeding the next —
 * matches the Swift `for ext in extensions { result = ... }` loop exactly.
 */
export function applyExtensions(dates: Date[], extensions: LEORuleExtension[]): Date[] {
  let result = dates
  for (const ext of extensions) {
    switch (ext) {
      case 'workdaysOnly':
        result = result.filter((d) => !isWeekend(d))
        break
      case 'skipUSHolidays':
        result = result.filter((d) => !isUSFederalHoliday(d))
        break
      case 'firstWeekdayOfMonth':
        // A map, not a filter — walks each date FORWARD past weekends/
        // holidays rather than dropping it. Confirmed from source; an
        // earlier design note guessed "walk forward" without the source in
        // front of it, so this pins the actual Swift behavior.
        result = result.map((d) => firstWeekdayIfNeeded(d))
        break
    }
  }
  return result
}

function isWeekend(date: Date): boolean {
  const wd = date.getDay() // 0=Sun … 6=Sat
  return wd === 0 || wd === 6
}

function firstWeekdayIfNeeded(date: Date): Date {
  let d = date
  while (isWeekend(d) || isUSFederalHoliday(d)) {
    d = new Date(d.getTime() + 86400_000)
  }
  return d
}
