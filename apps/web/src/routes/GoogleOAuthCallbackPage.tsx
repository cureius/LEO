import { useEffect, useRef, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { toast } from 'sonner'
import { exchangeCodeForTokens, fetchGoogleAccountEmail } from '@/google/oauth'
import { saveConnection } from '@/google/connection'
import { syncGoogleCalendarNow } from '@/google/sync'

/** Lands here after the user approves (or denies) the Google consent
 *  screen. Google redirects with either `?code=...` or `?error=...` in the
 *  query string — never both. */
export function GoogleOAuthCallbackPage() {
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const [error, setError] = useState<string | null>(null)
  const ranRef = useRef(false)

  useEffect(() => {
    // Effects run twice under StrictMode in dev — the authorization `code`
    // is single-use, so a second exchange attempt would fail with a
    // confusing "invalid_grant" even though the first one already succeeded.
    if (ranRef.current) return
    ranRef.current = true

    const oauthError = searchParams.get('error')
    if (oauthError) {
      setError(oauthError === 'access_denied' ? 'Access was denied.' : oauthError)
      return
    }

    const code = searchParams.get('code')
    if (!code) {
      setError('No authorization code received.')
      return
    }
    // Set only when this round-trip started from a "Reconnect" click on a
    // specific broken connection (see buildGoogleAuthUrl) — passing it
    // through to saveConnection overwrites that exact row by id rather than
    // upserting by email, which matters because the broken row's
    // google_email can be null (never successfully fetched).
    const reconnectConnectionId = searchParams.get('state') ?? undefined

    exchangeCodeForTokens(code)
      .then(async (tokens) => {
        if (!tokens.refresh_token) {
          // Only happens if this Google account had already granted consent
          // once before without `prompt=consent` taking effect for some
          // reason — buildGoogleAuthUrl always sets it, so this should be
          // rare, but there's nothing usable to store without it.
          throw new Error('Google did not return a refresh token — try disconnecting any prior access at myaccount.google.com/permissions and reconnecting.')
        }
        const googleEmail = await fetchGoogleAccountEmail(tokens.access_token)
        await saveConnection({
          accessToken: tokens.access_token,
          refreshToken: tokens.refresh_token,
          expiresAt: new Date(Date.now() + tokens.expires_in * 1000),
          googleEmail,
          connectionId: reconnectConnectionId,
        })
        toast.success(googleEmail ? `Connected ${googleEmail}` : 'Google Calendar connected')
        navigate('/settings', { replace: true })
        void syncGoogleCalendarNow()
      })
      .catch((err) => {
        setError(err instanceof Error ? err.message : String(err))
      })
  }, [searchParams, navigate])

  return (
    <div className="flex h-screen flex-col items-center justify-center gap-3 p-6 text-center">
      {error ? (
        <>
          <p className="text-sm font-medium text-danger">Couldn't connect Google Calendar</p>
          <p className="max-w-sm text-sm text-text-secondary">{error}</p>
          <button type="button" onClick={() => navigate('/settings')} className="text-sm text-accent hover:underline">
            Back to Settings
          </button>
        </>
      ) : (
        <p className="text-sm text-text-secondary">Connecting Google Calendar…</p>
      )}
    </div>
  )
}
