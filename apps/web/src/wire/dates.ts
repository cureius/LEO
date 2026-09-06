/**
 * `createdAt`/`updatedAt` inside every item/habit `data` payload are Swift's
 * default `JSONEncoder` `.deferredToDate` output: seconds since the Cocoa
 * reference date (2001-01-01T00:00:00Z), NOT Unix epoch. Confirmed against
 * real captured values, e.g. 803644207.08 and a negative birthDate
 * (-9849600, a date before 2001) in a real body_profiles row.
 *
 * This is a different convention from Anchor/Completion's ISO8601 strings —
 * see anchor.ts.
 */
export const COCOA_EPOCH_OFFSET_SECONDS = 978307200 // 2001-01-01T00:00:00Z minus 1970-01-01T00:00:00Z

export function refDateToJSDate(seconds: number): Date {
  return new Date((seconds + COCOA_EPOCH_OFFSET_SECONDS) * 1000)
}

export function jsDateToRefDate(date: Date): number {
  return date.getTime() / 1000 - COCOA_EPOCH_OFFSET_SECONDS
}
