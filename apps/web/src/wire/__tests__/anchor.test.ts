import { describe, expect, it } from 'vitest'
import {
  anchorIsUntimed,
  anchorOnComplete,
  anchorSortDate,
  anchorSortPriority,
  completionCompletedAt,
  completionIsFinished,
  decodeAnchor,
  decodeCompletion,
  encodeAnchor,
  encodeCompletion,
  shiftAnchorMinutes,
  type Anchor,
  type Completion,
} from '../anchor'

const anchorVariants: Anchor[] = [
  { type: 'untimed' },
  { type: 'dueAt', date: '2026-05-10T09:00:00.000Z' },
  { type: 'timeBlock', start: '2026-05-10T09:00:00.000Z', end: '2026-05-10T10:00:00.000Z' },
  { type: 'point', date: '2026-05-10T09:00:00.000Z' },
  {
    type: 'location',
    trigger: { coordinate: { latitude: 12.9716, longitude: 77.5946 }, radiusMeters: 100, direction: 'entering' },
  },
]

const completionVariants: Completion[] = [
  { type: 'open' },
  { type: 'completed', date: '2026-05-10T09:05:00.000Z' },
  { type: 'skipped', date: '2026-05-10T09:05:00.000Z', reason: 'too tired' },
  { type: 'skipped', date: '2026-05-10T09:05:00.000Z' }, // reason omitted, not null
  { type: 'dismissed' },
]

describe('Anchor round-trip', () => {
  for (const anchor of anchorVariants) {
    it(`round-trips ${anchor.type}`, () => {
      const decoded = decodeAnchor(encodeAnchor(anchor))
      expect(decoded).toEqual(anchor)
    })
  }
})

describe('Completion round-trip', () => {
  for (const completion of completionVariants) {
    it(`round-trips ${completion.type}${'reason' in completion ? ` (reason=${completion.reason})` : ''}`, () => {
      const decoded = decodeCompletion(encodeCompletion(completion))
      expect(decoded).toEqual(completion)
    })
  }
})

describe('anchorSortDate — port of Anchor.sortDate', () => {
  it('untimed has no sort date', () => {
    expect(anchorSortDate({ type: 'untimed' })).toBeUndefined()
  })
  it('location has no sort date', () => {
    expect(
      anchorSortDate({
        type: 'location',
        trigger: { coordinate: { latitude: 0, longitude: 0 }, radiusMeters: 100, direction: 'entering' },
      }),
    ).toBeUndefined()
  })
  it('dueAt/point sort by their own date', () => {
    expect(anchorSortDate({ type: 'dueAt', date: '2026-05-10T09:00:00.000Z' })?.toISOString()).toBe(
      '2026-05-10T09:00:00.000Z',
    )
    expect(anchorSortDate({ type: 'point', date: '2026-05-10T09:00:00.000Z' })?.toISOString()).toBe(
      '2026-05-10T09:00:00.000Z',
    )
  })
  it('timeBlock sorts by its start, not end', () => {
    const anchor: Anchor = { type: 'timeBlock', start: '2026-05-10T09:00:00.000Z', end: '2026-05-10T10:00:00.000Z' }
    expect(anchorSortDate(anchor)?.toISOString()).toBe('2026-05-10T09:00:00.000Z')
  })
})

describe('anchorIsUntimed — strictly `.untimed` only, NOT `.location` too', () => {
  it('is true for untimed', () => {
    expect(anchorIsUntimed({ type: 'untimed' })).toBe(true)
  })
  it('is false for location (has no sortDate but is not "untimed")', () => {
    expect(
      anchorIsUntimed({
        type: 'location',
        trigger: { coordinate: { latitude: 0, longitude: 0 }, radiusMeters: 100, direction: 'entering' },
      }),
    ).toBe(false)
  })
  it('is false for every timed variant', () => {
    expect(anchorIsUntimed({ type: 'dueAt', date: '2026-05-10T09:00:00.000Z' })).toBe(false)
    expect(anchorIsUntimed({ type: 'point', date: '2026-05-10T09:00:00.000Z' })).toBe(false)
    expect(
      anchorIsUntimed({ type: 'timeBlock', start: '2026-05-10T09:00:00.000Z', end: '2026-05-10T10:00:00.000Z' }),
    ).toBe(false)
  })
})

describe('anchorSortPriority — port of Anchor.sortPriority', () => {
  it('orders point < dueAt < timeBlock < other', () => {
    expect(anchorSortPriority({ type: 'point', date: '2026-05-10T09:00:00.000Z' })).toBe(0)
    expect(anchorSortPriority({ type: 'dueAt', date: '2026-05-10T09:00:00.000Z' })).toBe(1)
    expect(
      anchorSortPriority({ type: 'timeBlock', start: '2026-05-10T09:00:00.000Z', end: '2026-05-10T10:00:00.000Z' }),
    ).toBe(2)
    expect(anchorSortPriority({ type: 'untimed' })).toBe(3)
  })
})

describe('completionIsFinished — port of Completion.isFinished', () => {
  it('open is the only non-finished state', () => {
    expect(completionIsFinished({ type: 'open' })).toBe(false)
    expect(completionIsFinished({ type: 'completed', date: '2026-05-10T09:05:00.000Z' })).toBe(true)
    expect(completionIsFinished({ type: 'skipped', date: '2026-05-10T09:05:00.000Z' })).toBe(true)
    expect(completionIsFinished({ type: 'dismissed' })).toBe(true)
  })
})

describe('shiftAnchorMinutes — day-timeline drag-to-reschedule (web-only)', () => {
  it('shifts dueAt/point by the given number of minutes', () => {
    expect(shiftAnchorMinutes({ type: 'dueAt', date: '2026-05-10T09:00:00.000Z' }, 30)).toEqual({
      type: 'dueAt',
      date: '2026-05-10T09:30:00.000Z',
    })
    expect(shiftAnchorMinutes({ type: 'point', date: '2026-05-10T09:00:00.000Z' }, -45)).toEqual({
      type: 'point',
      date: '2026-05-10T08:15:00.000Z',
    })
  })

  it('shifts both start and end of a timeBlock, preserving duration', () => {
    const anchor: Anchor = { type: 'timeBlock', start: '2026-05-10T09:00:00.000Z', end: '2026-05-10T10:00:00.000Z' }
    expect(shiftAnchorMinutes(anchor, 90)).toEqual({
      type: 'timeBlock',
      start: '2026-05-10T10:30:00.000Z',
      end: '2026-05-10T11:30:00.000Z',
    })
  })

  it('is a no-op for a zero delta, untimed, and location anchors', () => {
    const dueAt: Anchor = { type: 'dueAt', date: '2026-05-10T09:00:00.000Z' }
    expect(shiftAnchorMinutes(dueAt, 0)).toEqual(dueAt)
    expect(shiftAnchorMinutes({ type: 'untimed' }, 30)).toEqual({ type: 'untimed' })
    const location: Anchor = {
      type: 'location',
      trigger: { coordinate: { latitude: 0, longitude: 0 }, radiusMeters: 100, direction: 'entering' },
    }
    expect(shiftAnchorMinutes(location, 30)).toEqual(location)
  })
})

describe('anchorOnComplete — pin a backlog item to the moment it was completed', () => {
  const now = new Date('2026-05-10T09:05:00.000Z')

  it('turns an untimed anchor into dueAt at `now`', () => {
    expect(anchorOnComplete({ type: 'untimed' }, now)).toEqual({ type: 'dueAt', date: now.toISOString() })
  })

  it('leaves an already-timed anchor untouched', () => {
    const dueAt: Anchor = { type: 'dueAt', date: '2026-05-10T09:00:00.000Z' }
    expect(anchorOnComplete(dueAt, now)).toEqual(dueAt)

    const timeBlock: Anchor = { type: 'timeBlock', start: '2026-05-10T09:00:00.000Z', end: '2026-05-10T10:00:00.000Z' }
    expect(anchorOnComplete(timeBlock, now)).toEqual(timeBlock)

    const point: Anchor = { type: 'point', date: '2026-05-10T09:00:00.000Z' }
    expect(anchorOnComplete(point, now)).toEqual(point)
  })

  it('leaves a location anchor untouched — not "untimed" per anchorIsUntimed', () => {
    const location: Anchor = {
      type: 'location',
      trigger: { coordinate: { latitude: 0, longitude: 0 }, radiusMeters: 100, direction: 'entering' },
    }
    expect(anchorOnComplete(location, now)).toEqual(location)
  })
})

describe('completionCompletedAt', () => {
  it('returns the date only for `completed`', () => {
    expect(completionCompletedAt({ type: 'completed', date: '2026-05-10T09:05:00.000Z' })?.toISOString()).toBe(
      '2026-05-10T09:05:00.000Z',
    )
    expect(completionCompletedAt({ type: 'skipped', date: '2026-05-10T09:05:00.000Z' })).toBeUndefined()
    expect(completionCompletedAt({ type: 'open' })).toBeUndefined()
  })
})
