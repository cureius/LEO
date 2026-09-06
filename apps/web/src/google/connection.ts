import { supabase } from '@/lib/supabaseClient'
import { refreshAccessToken } from './oauth'

export type GoogleConnection = {
  id: string
  accessToken: string
  refreshToken: string
  expiresAt: Date
  calendarId: string
  googleEmail: string | undefined
  needsReauth: boolean
  lastSyncError: string | undefined
}

type ConnectionRow = {
  id: string
  access_token: string
  refresh_token: string
  expires_at: string
  calendar_id: string
  google_email: string | null
  needs_reauth: boolean
  last_sync_error: string | null
}

const CONNECTION_COLUMNS = 'id, access_token, refresh_token, expires_at, calendar_id, google_email, needs_reauth, last_sync_error'

function rowToConnection(row: ConnectionRow): GoogleConnection {
  return {
    id: row.id,
    accessToken: row.access_token,
    refreshToken: row.refresh_token,
    expiresAt: new Date(row.expires_at),
    calendarId: row.calendar_id,
    googleEmail: row.google_email ?? undefined,
    needsReauth: row.needs_reauth,
    lastSyncError: row.last_sync_error ?? undefined,
  }
}

async function currentUserId(): Promise<string> {
  const { data } = await supabase.auth.getSession()
  const userId = data.session?.user.id
  if (!userId) throw new Error('Not signed in')
  return userId
}

export async function getConnections(): Promise<GoogleConnection[]> {
  const { data, error } = await supabase
    .from('google_calendar_connections')
    .select(CONNECTION_COLUMNS)
    .order('created_at', { ascending: true })
  if (error) throw error
  return (data as ConnectionRow[]).map(rowToConnection)
}

export async function getConnectionById(id: string): Promise<GoogleConnection | null> {
  const { data, error } = await supabase
    .from('google_calendar_connections')
    .select(CONNECTION_COLUMNS)
    .eq('id', id)
    .maybeSingle()
  if (error) throw error
  return data ? rowToConnection(data as ConnectionRow) : null
}

/** Upserts by (user_id, google_email) — reconnecting an already-connected
 *  Google account updates its existing row instead of accumulating a
 *  duplicate connection for the same account (matches the unique index
 *  added in migration 0004). A brand new account (or one connected before
 *  email scope existed, googleEmail undefined) always inserts a new row. */
export async function saveConnection(tokens: {
  accessToken: string
  refreshToken: string
  expiresAt: Date
  googleEmail: string | undefined
  connectionId?: string
}): Promise<GoogleConnection> {
  const userId = await currentUserId()
  const row: Record<string, unknown> = {
    user_id: userId,
    access_token: tokens.accessToken,
    refresh_token: tokens.refreshToken,
    expires_at: tokens.expiresAt.toISOString(),
    google_email: tokens.googleEmail ?? null,
  }
  if (tokens.connectionId) row.id = tokens.connectionId
  // A successful (re)connect always means the new refresh token is good —
  // clear any stale reauth flag/error left over from before this token was
  // obtained, otherwise a freshly-reconnected account would still show as
  // broken in the UI until the next sync pass happened to succeed.
  row.needs_reauth = false
  row.last_sync_error = null

  const { data, error } = await supabase
    .from('google_calendar_connections')
    .upsert(row, tokens.connectionId ? { onConflict: 'id' } : { onConflict: 'user_id,google_email' })
    .select(CONNECTION_COLUMNS)
    .single()
  if (error) throw error
  return rowToConnection(data as ConnectionRow)
}

export async function disconnectGoogleCalendar(connectionId: string): Promise<void> {
  const { error } = await supabase.from('google_calendar_connections').delete().eq('id', connectionId)
  if (error) throw error
}

/** Records the outcome of a sync attempt against an EXISTING connection's
 *  row without touching its tokens — separate from saveConnection, which
 *  always writes a full token set. `needsReauth: true` means the stored
 *  refresh token is dead (Google returned invalid_grant) and nothing short
 *  of the user re-consenting via the OAuth flow again will fix it; a
 *  regular failed sync pass (network blip, Calendar API hiccup) records the
 *  error message for visibility but leaves needsReauth alone. */
export async function markConnectionHealth(connectionId: string, health: { needsReauth: boolean; lastSyncError: string | null }): Promise<void> {
  const { error } = await supabase
    .from('google_calendar_connections')
    .update({ needs_reauth: health.needsReauth, last_sync_error: health.lastSyncError })
    .eq('id', connectionId)
  if (error) throw error
}

// Refreshed this far ahead of the real expiry, not right at it — a token
// that expires mid-flight through a batch of Calendar API calls (list, then
// several inserts/updates) would otherwise fail partway rather than never.
const REFRESH_MARGIN_MS = 5 * 60_000

/** Returns a definitely-valid access token for ONE connection, refreshing
 *  and persisting a new one first if the stored token is expired or close
 *  to it. Every Calendar API call in this module goes through this rather
 *  than reading the stored token directly. */
export async function getValidAccessToken(connection: GoogleConnection): Promise<string> {
  if (connection.expiresAt.getTime() - Date.now() > REFRESH_MARGIN_MS) {
    return connection.accessToken
  }

  const refreshed = await refreshAccessToken(connection.refreshToken)
  const expiresAt = new Date(Date.now() + refreshed.expires_in * 1000)
  await saveConnection({
    connectionId: connection.id,
    accessToken: refreshed.access_token,
    refreshToken: connection.refreshToken,
    expiresAt,
    googleEmail: connection.googleEmail,
  })
  return refreshed.access_token
}
