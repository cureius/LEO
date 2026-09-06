import { describe, expect, it } from 'vitest'
import { googleEventToItem, itemToGoogleEvent } from '../mapping'
import type { GoogleEvent } from '../calendarApi'
import type { EventItem } from '@/domain/types'

const now = new Date('2026-07-29T09:00:00.000Z')

function event(item: EventItem): EventItem {
  return item
}

describe('itemToGoogleEvent', () => {
  const base: EventItem = {
    kind: 'event',
    id: 'i1',
    title: 'Daily huddle',
    createdAt: now,
    updatedAt: now,
    importance: 1,
    anchor: { type: 'timeBlock', start: '2026-07-29T10:00:00.000Z', end: '2026-07-29T10:30:00.000Z' },
    completion: { type: 'open' },
    tags: [],
    attendees: ['boss@company.com', 'me@company.com'],
  }

  // Regression test: marking an event done (or any other edit) pushed a
  // bare {email}-only attendees array back to Google, which PATCHes as a
  // full replacement and resets every attendee's RSVP (responseStatus) to
  // "needsAction" — silently wiping a prior "Yes". LEO has no attendee-
  // editing UI, so the fix is to never send `attendees` at all.
  it('never includes an attendees field, even when the item has attendees', () => {
    const payload = itemToGoogleEvent(event(base))
    expect(payload).not.toHaveProperty('attendees')
  })

  it('still sends title/description/location/time', () => {
    const payload = itemToGoogleEvent(event({ ...base, notes: 'bring laptop', location: 'Room 4' }))
    expect(payload).toMatchObject({
      summary: 'Daily huddle',
      description: 'bring laptop',
      location: 'Room 4',
      start: { dateTime: '2026-07-29T10:00:00.000Z' },
      end: { dateTime: '2026-07-29T10:30:00.000Z' },
    })
  })
})

describe('googleEventToItem', () => {
  it('still extracts attendee emails when pulling FROM Google (read path unaffected by the push fix)', () => {
    const googleEvent: GoogleEvent = {
      id: 'g1',
      summary: 'Daily huddle',
      start: { dateTime: '2026-07-29T10:00:00.000Z' },
      end: { dateTime: '2026-07-29T10:30:00.000Z' },
      attendees: [{ email: 'boss@company.com' }, { email: 'me@company.com' }],
    }
    const item = googleEventToItem(googleEvent)
    expect(item.attendees).toEqual(['boss@company.com', 'me@company.com'])
  })
})
