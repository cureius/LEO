const GOOGLE_CLIENT_ID = import.meta.env.VITE_GOOGLE_CLIENT_ID as string | undefined
// email/profile — not for calendar access itself, but so each connected
// account can be labeled by its actual address (see fetchGoogleAccountEmail
// below); multiple connections are indistinguishable in the UI without it.
const SCOPE = 'https://www.googleapis.com/auth/calendar email profile'

export function isGoogleOAuthConfigured(): boolean {
  return !!GOOGLE_CLIENT_ID
}

export function googleOAuthRedirectUri(): string {
  return `${window.location.origin}/oauth/google/callback`
}

/** `access_type=offline` + `prompt=consent` — without both, Google only
 *  returns a refresh_token on a user's very FIRST-ever consent for this
 *  client; a reconnect after disconnecting would silently get an
 *  access-token-only response with nothing to refresh from later.
 *  `select_account` — without it, clicking "Add another account" while
 *  already signed into Google in this browser silently reauthorizes the
 *  SAME account currently active rather than offering a picker, making it
 *  impossible to ever add a second one.
 *
 *  `reconnectConnectionId` — when re-authorizing a specific broken
 *  connection (dead refresh token), passed through as `state` so the
 *  callback overwrites that exact row (by id) instead of upserting by
 *  email — the row that needs fixing may have a null google_email (never
 *  successfully fetched), so email-based upsert can't reliably target it. */
export function buildGoogleAuthUrl(reconnectConnectionId?: string): string {
  if (!GOOGLE_CLIENT_ID) throw new Error('VITE_GOOGLE_CLIENT_ID is not configured')
  const params = new URLSearchParams({
    client_id: GOOGLE_CLIENT_ID,
    redirect_uri: googleOAuthRedirectUri(),
    response_type: 'code',
    scope: SCOPE,
    access_type: 'offline',
    prompt: 'select_account consent',
  })
  if (reconnectConnectionId) params.set('state', reconnectConnectionId)
  return `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`
}

/** Which Google account was just connected — there's no other way to tell
 *  two connections apart in the UI (Google never includes this in the
 *  token response itself, only via a separate userinfo call). */
export async function fetchGoogleAccountEmail(accessToken: string): Promise<string | undefined> {
  const response = await fetch('https://www.googleapis.com/oauth2/v2/userinfo', {
    headers: { Authorization: `Bearer ${accessToken}` },
  })
  if (!response.ok) return undefined
  const json = await response.json()
  return typeof json?.email === 'string' ? json.email : undefined
}

export type TokenResponse = { access_token: string; refresh_token?: string; expires_in: number }

/** Google's OAuth2 error CODE (not the human-readable description) for a
 *  refresh token that's dead — expired, revoked, or invalidated by a
 *  security event. Thrown as its own class so callers refreshing an
 *  existing connection's token can tell "this connection needs the user to
 *  re-consent" apart from a transient failure (network blip, our proxy
 *  misconfigured) that's worth retrying rather than flagging. */
export class GoogleInvalidGrantError extends Error {}

async function parseTokenResponse(response: Response): Promise<TokenResponse> {
  const json = await response.json()
  if (!response.ok) {
    // Two different error shapes to account for: Google's OAuth endpoint
    // itself returns {error, error_description} (flat strings), but this
    // same code path also surfaces failures from OUR dev/prod proxy
    // (missing config, network failure reaching Google) which use
    // {error: {message}} — matching claude.ts's convention elsewhere in
    // this app. Confirmed live: without checking the nested shape too, a
    // real "not configured" message from the proxy silently collapsed into
    // the generic "Google OAuth error 500" fallback below, with no way to
    // tell what was actually wrong.
    const message =
      typeof json?.error_description === 'string'
        ? json.error_description
        : typeof json?.error === 'string'
          ? json.error
          : typeof json?.error?.message === 'string'
            ? json.error.message
            : `Google OAuth error ${response.status}`
    if (json?.error === 'invalid_grant') throw new GoogleInvalidGrantError(message)
    throw new Error(message)
  }
  return json as TokenResponse
}

/** The one step in this whole flow that must go through a backend — see
 *  api/google-oauth-exchange.ts's doc comment. */
export async function exchangeCodeForTokens(code: string): Promise<TokenResponse> {
  const response = await fetch('/api/google-oauth-exchange', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code, redirectUri: googleOAuthRedirectUri() }),
  })
  return parseTokenResponse(response)
}

export async function refreshAccessToken(refreshToken: string): Promise<TokenResponse> {
  const response = await fetch('/api/google-oauth-refresh', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refreshToken }),
  })
  return parseTokenResponse(response)
}
