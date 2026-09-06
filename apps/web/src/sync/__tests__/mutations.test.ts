import { describe, expect, it } from 'vitest'
import { errorMessage } from '../mutations'

describe('errorMessage', () => {
  // Caught live: a rollback toast rendered the literal string "[object
  // Object]" because Supabase's PostgrestError is a plain object, not an
  // Error instance, and the original code did `String(err)` unconditionally.
  it('extracts .message from a real Error instance', () => {
    expect(errorMessage(new TypeError('Failed to fetch'))).toBe('Failed to fetch')
  })

  it('extracts .message from a plain PostgrestError-shaped object', () => {
    expect(errorMessage({ message: 'permission denied for table items', code: '42501' })).toBe(
      'permission denied for table items',
    )
  })

  it('falls back to String() only for a value with no usable .message', () => {
    expect(errorMessage('a plain string reason')).toBe('a plain string reason')
    expect(errorMessage(42)).toBe('42')
  })

  it('never renders the useless "[object Object]" for a plain object that lacks .message', () => {
    const result = errorMessage({ code: '42501' })
    expect(result).not.toBe('[object Object]')
  })
})
