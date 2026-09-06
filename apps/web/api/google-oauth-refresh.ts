export const config = { runtime: 'edge' }

/** Same reasoning as google-oauth-exchange.ts — the `refresh_token` grant
 *  also requires `client_secret`, so refreshing an expired access token has
 *  to go through here rather than being called directly from the browser. */
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

  let body: { refreshToken?: string }
  try {
    body = await req.json()
  } catch {
    return new Response(JSON.stringify({ error: { message: 'Invalid JSON body' } }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    })
  }
  if (!body.refreshToken) {
    return new Response(JSON.stringify({ error: { message: 'Missing refreshToken' } }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      refresh_token: body.refreshToken,
      client_id: clientId,
      client_secret: clientSecret,
      grant_type: 'refresh_token',
    }),
  })

  const text = await tokenResponse.text()
  return new Response(text, {
    status: tokenResponse.status,
    headers: { 'Content-Type': 'application/json' },
  })
}
