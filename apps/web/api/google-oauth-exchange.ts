export const config = { runtime: 'edge' }

/**
 * Exchanges an OAuth authorization code for Google's access/refresh tokens.
 * Must happen server-side: the `authorization_code` grant requires
 * `client_secret`, which can never reach the browser bundle — this is the
 * one step in the whole Google Calendar flow that isn't safe to do
 * client-side, unlike the actual Calendar API calls (which just need a
 * valid Bearer access token and work fine directly from the browser).
 */
export default async function handler(req: Request): Promise<Response> {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  const clientId = process.env.VITE_GOOGLE_CLIENT_ID
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET
  if (!clientId || !clientSecret) {
    return new Response(JSON.stringify({ error: { message: 'Google OAuth is not configured on the server' } }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  let body: { code?: string; redirectUri?: string }
  try {
    body = await req.json()
  } catch {
    return new Response(JSON.stringify({ error: { message: 'Invalid JSON body' } }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    })
  }
  if (!body.code || !body.redirectUri) {
    return new Response(JSON.stringify({ error: { message: 'Missing code or redirectUri' } }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      code: body.code,
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri: body.redirectUri,
      grant_type: 'authorization_code',
    }),
  })

  const text = await tokenResponse.text()
  return new Response(text, {
    status: tokenResponse.status,
    headers: { 'Content-Type': 'application/json' },
  })
}
