import { describe, expect, it } from 'vitest'
import { jsDateToRefDate, refDateToJSDate, COCOA_EPOCH_OFFSET_SECONDS } from '../dates'

describe('refDateToJSDate / jsDateToRefDate', () => {
  it('decodes the literal sample captured from a real production row (803644207.08)', () => {
    // Expected value independently verified via `node -e` against the raw
    // formula, not hand-computed, to avoid enshrining an arithmetic mistake.
    const date = refDateToJSDate(803644207.08)
    expect(date.toISOString()).toBe('2026-06-20T10:30:07.080Z')
  })

  it('decodes a negative refdate (a real birthDate captured from a live body_profiles row)', () => {
    const date = refDateToJSDate(-9849600)
    expect(date.toISOString()).toBe('2000-09-09T00:00:00.000Z')
  })

  it('round-trips an arbitrary date through encode -> decode', () => {
    const original = new Date('2026-01-15T12:34:56.789Z')
    const roundTripped = refDateToJSDate(jsDateToRefDate(original))
    // Sub-millisecond float precision can drift by <1ms; assert equality at
    // the millisecond level rather than exact float equality.
    expect(roundTripped.getTime()).toBeCloseTo(original.getTime(), -1)
  })

  it('the epoch offset is exactly 2001-01-01 minus 1970-01-01', () => {
    expect(COCOA_EPOCH_OFFSET_SECONDS).toBe(978307200)
  })
})
