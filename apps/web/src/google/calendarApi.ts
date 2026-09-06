/**
 * Thin wrapper over Google Calendar API v3. Called directly from the
 * browser with a Bearer access token — unlike the OAuth token endpoints,
 * Google's Calendar API itself supports CORS for authenticated requests
 * (it's what Google's own JS client libraries do), so no backend proxy is
 * needed for the actual data calls.
 */
const BASE_URL = 'https://www.googleapis.com/calendar/v3'

export type GoogleEventTime = { dateTime?: string; date?: string; timeZone?: string }

export type GoogleEvent = {
  id: string
  status?: 'confirmed' | 'tentative' | 'cancelled'
  summary?: string
  description?: string
  location?: string
  start: GoogleEventTime
  end: GoogleEventTime
  attendees?: { email: string }[]
  created?: string
  updated?: string
  /** Only present on an expanded occurrence of a recurring event (what
   *  `singleEvents=true` returns) — the id of the series' master event,
   *  shared by every occurrence in that series. Absent on one-off events.
   *  Used to detect/cap recurring-event sync, not to look up the master
   *  event itself (never fetched). */
  recurringEventId?: string
}

async function request<T>(accessToken: string, path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${BASE_URL}${path}`, {
    ...init,
    headers: { ...init?.headers, Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
  })
  if (!response.ok) {
    const text = await response.text().catch(() => '')
    throw new Error(`Google Calendar API error ${response.status}: ${text}`)
  }
  if (response.status === 204) return undefined as T
  return response.json() as Promise<T>
}

/** `showDeleted=true` + checking `status === 'cancelled'` on the results is
 *  how a since-deleted Google event surfaces at all in a plain list call —
 *  without it, a deleted event just silently stops appearing, which reads
 *  identically to "never existed" and there'd be no way to mirror the
 *  deletion into LEO. `singleEvents=true` expands recurring events into
 *  individual instances server-side, so this module never has to parse
 *  RRULEs itself. */
export async function listGoogleEvents(
  accessToken: string,
  calendarId: string,
  range: { timeMin: string; timeMax: string },
): Promise<GoogleEvent[]> {
  const params = new URLSearchParams({
    timeMin: range.timeMin,
    timeMax: range.timeMax,
    singleEvents: 'true',
    showDeleted: 'true',
    orderBy: 'startTime',
    maxResults: '250',
  })
  const result = await request<{ items: GoogleEvent[] }>(accessToken, `/calendars/${encodeURIComponent(calendarId)}/events?${params.toString()}`)
  return result.items
}

export async function insertGoogleEvent(accessToken: string, calendarId: string, event: Partial<GoogleEvent>): Promise<GoogleEvent> {
  return request<GoogleEvent>(accessToken, `/calendars/${encodeURIComponent(calendarId)}/events`, {
    method: 'POST',
    body: JSON.stringify(event),
  })
}

export async function updateGoogleEvent(accessToken: string, calendarId: string, eventId: string, event: Partial<GoogleEvent>): Promise<GoogleEvent> {
  return request<GoogleEvent>(accessToken, `/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(eventId)}`, {
    method: 'PATCH',
    body: JSON.stringify(event),
  })
}

export async function deleteGoogleEvent(accessToken: string, calendarId: string, eventId: string): Promise<void> {
  try {
    await request<undefined>(accessToken, `/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(eventId)}`, { method: 'DELETE' })
  } catch (err) {
    // Already gone (e.g. deleted directly in Google Calendar too, or this is
    // a retry of an already-succeeded delete) — not a real failure.
    if (err instanceof Error && err.message.includes('404')) return
    if (err instanceof Error && err.message.includes('410')) return
    throw err
  }
}
