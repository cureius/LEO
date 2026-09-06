/**
 * UTF-8-safe base64 helpers for decoding/encoding the JSON sub-blobs Swift
 * stores base64-encoded inside `data` (anchorB64, completionB64,
 * plannedExercisesB64, etc.). Plain atob/btoa only handle Latin1, which
 * silently mangles any non-ASCII byte — go through TextEncoder/TextDecoder
 * instead so this is correct for any payload, not just the ASCII-only ones
 * we happen to have seen so far.
 */

function base64ToBytes(base64: string): Uint8Array {
  const binString = atob(base64)
  return Uint8Array.from(binString, (m) => m.codePointAt(0)!)
}

function bytesToBase64(bytes: Uint8Array): string {
  const binString = Array.from(bytes, (byte) => String.fromCodePoint(byte)).join('')
  return btoa(binString)
}

export function decodeBase64Json<T>(b64: string): T {
  const bytes = base64ToBytes(b64)
  const text = new TextDecoder().decode(bytes)
  return JSON.parse(text) as T
}

export function encodeJsonBase64(value: unknown): string {
  const text = JSON.stringify(value)
  const bytes = new TextEncoder().encode(text)
  return bytesToBase64(bytes)
}
