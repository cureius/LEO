import type { GoogleEvent } from './calendarApi'
import type { Anchor } from '@/wire/anchor'
import type { EventItem } from '@/domain/types'

/** Builds/refreshes an EventItem from a Google event. `existing` — when
 *  provided (this Google event is already linked to a local item) — carries
 *  forward fields Google has no concept of (tags, importance, completion,
 *  the local id) rather than clobbering them every sync pass; when absent,
 *  this is a brand-new item being created from a Google event LEO has
 *  never seen before. */
export function googleEventToItem(event: GoogleEvent, existing?: EventItem): EventItem {
  const anchor = googleTimeToAnchor(event)
  return {
    kind: 'event',
    id: existing?.id ?? crypto.randomUUID(),
    title: event.summary || '(untitled)',
    notes: event.description || undefined,
    createdAt: existing?.createdAt ?? (event.created ? new Date(event.created) : new Date()),
    updatedAt: event.updated ? new Date(event.updated) : new Date(),
    importance: existing?.importance ?? 1,
    anchor,
    completion: existing?.completion ?? { type: 'open' },
    tags: existing?.tags ?? [],
    location: event.location || undefined,
    attendees: (event.attendees ?? []).map((a) => a.email),
    rruleRaw: existing?.rruleRaw,
  }
}

function googleTimeToAnchor(event: GoogleEvent): Anchor {
  if (event.start.dateTime) {
    return { type: 'timeBlock', start: event.start.dateTime, end: event.end.dateTime ?? event.start.dateTime }
  }
  if (event.start.date) {
    // All-day event — Google has no time-of-day here at all; `dueAt` is the
    // closest existing Anchor variant (there's no dedicated all-day type).
    return { type: 'dueAt', date: event.start.date }
  }
  return { type: 'untimed' }
}

/** Reverse direction — what gets pushed TO Google when a linked item is
 *  edited in LEO. Only `timeBlock`/`dueAt`/`point` anchors have a sensible
 *  Google representation; `untimed`/`location` items shouldn't be linked to
 *  a calendar event in the first place, so this only needs to handle the
 *  cases a Google-originated item can actually be in.
 *
 *  Deliberately omits `attendees`. `EventItem.attendees` is just a flat
 *  `string[]` of emails (see googleEventToItem above) — it was never
 *  carrying each attendee's `responseStatus`/`self`/`organizer` because
 *  `GoogleEvent`'s attendee type never captured those to begin with.
 *  Sending `{ email }`-only objects back to Google's PATCH endpoint doesn't
 *  merge with the existing attendee list — it REPLACES it, silently
 *  resetting every attendee's RSVP (including the user's own) to
 *  "needsAction". Confirmed live: marking an event done in LEO (any edit
 *  that pushes back, not just completion) was wiping a prior "Yes" RSVP.
 *  LEO's UI never offers attendee editing in the first place (read-only in
 *  ItemDetailPanel), so there's nothing to legitimately push here — and
 *  `updateGoogleEvent` uses PATCH, which leaves omitted fields (including
 *  attendees) untouched on Google's side. */
export function itemToGoogleEvent(item: EventItem): Partial<GoogleEvent> {
  return {
    summary: item.title,
    description: item.notes,
    location: item.location,
    ...anchorToGoogleTime(item.anchor),
  }
}

function anchorToGoogleTime(anchor: Anchor): { start: GoogleEvent['start']; end: GoogleEvent['end'] } {
  if (anchor.type === 'timeBlock') return { start: { dateTime: anchor.start }, end: { dateTime: anchor.end } }
  if (anchor.type === 'dueAt' || anchor.type === 'point') return { start: { dateTime: anchor.date }, end: { dateTime: anchor.date } }
  // untimed/location — no real Google representation; zero-duration "now" is
  // a defensive fallback, not expected to be hit in practice (see doc comment).
  const now = new Date().toISOString()
  return { start: { dateTime: now }, end: { dateTime: now } }
}
