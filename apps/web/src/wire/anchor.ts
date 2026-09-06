import { decodeBase64Json, encodeJsonBase64 } from './base64'

/**
 * Anchor/Completion are base64-encoded JSON sub-blobs inside every item's
 * `data` payload. Unlike the outer createdAt/updatedAt (Cocoa reference-date
 * floats, see dates.ts), dates *inside* these sub-blobs are ISO8601 strings —
 * confirmed in LEO/Persistence/Mapping/ItemMapping.swift, which uses a
 * separately configured JSONEncoder/Decoder with `.iso8601` for exactly
 * these two types. Two different date conventions in the same payload.
 */

export type LocationTrigger = {
  coordinate: { latitude: number; longitude: number }
  radiusMeters: number
  direction: 'entering' | 'leaving'
}

export type Anchor =
  | { type: 'untimed' }
  | { type: 'dueAt'; date: string }
  | { type: 'timeBlock'; start: string; end: string }
  | { type: 'point'; date: string }
  | { type: 'location'; trigger: LocationTrigger }

export type Completion =
  | { type: 'open' }
  | { type: 'completed'; date: string }
  | { type: 'skipped'; date: string; reason?: string }
  | { type: 'dismissed' }

export function decodeAnchor(b64: string): Anchor {
  return decodeBase64Json<Anchor>(b64)
}

export function encodeAnchor(anchor: Anchor): string {
  return encodeJsonBase64(anchor)
}

export function decodeCompletion(b64: string): Completion {
  return decodeBase64Json<Completion>(b64)
}

export function encodeCompletion(completion: Completion): string {
  return encodeJsonBase64(completion)
}

/** The date used for chronological ordering — port of Anchor.sortDate (Anchor.swift:19-27). */
export function anchorSortDate(anchor: Anchor): Date | undefined {
  switch (anchor.type) {
    case 'untimed':
      return undefined
    case 'dueAt':
    case 'point':
      return new Date(anchor.date)
    case 'timeBlock':
      return new Date(anchor.start)
    case 'location':
      return undefined
  }
}

/**
 * Port of Anchor.isUntimed (Anchor.swift:29-32) — true ONLY for `.untimed`.
 * `.location` also has no sortDate but is a distinct case, not "untimed";
 * conflating the two was an early mistake here, caught by re-reading source
 * rather than trusting a first guess.
 */
export function anchorIsUntimed(anchor: Anchor): boolean {
  return anchor.type === 'untimed'
}

/** When this anchor's occupied time actually ends — `timeBlock`'s real
 *  `end`, or the same instant as sortDate for anything else (a `dueAt`/
 *  `point` has no duration to speak of). Used to find "right after the
 *  previous task" when appending a dropped backlog item to the end of a
 *  day's schedule (TodayPage.tsx) — sortDate alone would only ever give
 *  the START of the last item, which is what's already being sorted by. */
export function anchorEndDate(anchor: Anchor): Date | undefined {
  return anchor.type === 'timeBlock' ? new Date(anchor.end) : anchorSortDate(anchor)
}

/**
 * Secondary sort key for items sharing the same sortDate — port of
 * Anchor.sortPriority (Anchor.swift:37-44). Point-in-time items (reminders,
 * alarms) fire at an exact moment and should appear before time blocks that
 * merely *begin* at that moment.
 */
export function anchorSortPriority(anchor: Anchor): number {
  switch (anchor.type) {
    case 'point':
      return 0
    case 'dueAt':
      return 1
    case 'timeBlock':
      return 2
    default:
      return 3
  }
}

/** Port of Completion.isFinished (Completion.swift:11-16) — open is the only non-finished state. */
export function completionIsFinished(completion: Completion): boolean {
  return completion.type !== 'open'
}

/** Port of Completion.completedAt (Completion.swift:19-22). */
export function completionCompletedAt(completion: Completion): Date | undefined {
  return completion.type === 'completed' ? new Date(completion.date) : undefined
}

/** What an item's anchor should become when it's checked off from the
 *  backlog. An untimed item has no sortDate at all, so the moment it's
 *  completed it would otherwise vanish off every day view (TodayPage
 *  filters/groups everything by anchorSortDate) with no record of when it
 *  actually got done — pinning it to "now" fixes both. Anything already
 *  timed (dueAt/timeBlock/point/location) keeps its own anchor untouched;
 *  this only ever affects items that had none. Web-only addition, same
 *  category as shiftAnchorMinutes below. */
export function anchorOnComplete(anchor: Anchor, now: Date = new Date()): Anchor {
  return anchorIsUntimed(anchor) ? { type: 'dueAt', date: now.toISOString() } : anchor
}

/**
 * Shift a timed anchor by `deltaMinutes`, preserving duration for
 * `timeBlock`. Web-only addition — drives the Today page's drag-to-reschedule
 * timeline (DayTimeline.tsx); there is no Swift equivalent since neither
 * native app has a drag gesture for repositioning an item's time.
 */
export function shiftAnchorMinutes(anchor: Anchor, deltaMinutes: number): Anchor {
  if (deltaMinutes === 0) return anchor
  switch (anchor.type) {
    case 'dueAt':
    case 'point':
      return { ...anchor, date: new Date(new Date(anchor.date).getTime() + deltaMinutes * 60_000).toISOString() }
    case 'timeBlock':
      return {
        ...anchor,
        start: new Date(new Date(anchor.start).getTime() + deltaMinutes * 60_000).toISOString(),
        end: new Date(new Date(anchor.end).getTime() + deltaMinutes * 60_000).toISOString(),
      }
    case 'untimed':
    case 'location':
      return anchor
  }
}
