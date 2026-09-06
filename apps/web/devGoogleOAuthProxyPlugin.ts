import { loadEnv, type Plugin } from 'vite'

/**
 * Dev-only stand-in for api/google-oauth-exchange.ts and
 * api/google-oauth-refresh.ts — same reasoning as devProxyPlugin.ts's
 * devClaudeProxyPlugin: Vite's dev server doesn't run `api/*.ts` as
 * serverless functions, only Vercel does, so without this the whole Google
 * Calendar connect flow 404s under plain `pnpm dev`. Both endpoints are
 * small, non-streaming JSON-in/JSON-out calls to Google's token endpoint,
 * so one generic handler covers both rather than duplicating the plumbing.
 */
function readBody(req: import('http').IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = []
    req.on('data', (chunk) => chunks.push(chunk))
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')))
    req.on('error', reject)
  })
}

export function devGoogleOAuthProxyPlugin(): Plugin {
  return {
    name: 'dev-google-oauth-proxy',
    configureServer(server) {
      // NOT process.env — confirmed live: Vite does not expose .env.local's
      // values on process.env to plugin/config code just because they're
      // present in the file (that's a separate mechanism from import.meta.env,
      // which is also NOT available here since this runs in the Vite Node
      // process, not the browser bundle). loadEnv() with an empty prefix is
      // the actual documented way to read arbitrary (non-VITE_-prefixed)
      // env vars from plugin code — GOOGLE_CLIENT_SECRET deliberately has no
      // VITE_ prefix so it never ends up in the client bundle either.
      const env = loadEnv(server.config.mode, server.config.envDir ?? server.config.root, '')

      const register = (path: string, buildParams: (body: Record<string, unknown>) => URLSearchParams | { error: string }) => {
        server.middlewares.use(path, async (req, res) => {
          if (req.method !== 'POST') {
            res.statusCode = 405
            res.end('Method not allowed')
            return
          }

          const clientId = env.VITE_GOOGLE_CLIENT_ID
          const clientSecret = env.GOOGLE_CLIENT_SECRET
          if (!clientId || !clientSecret) {
            res.statusCode = 500
            res.setHeader('Content-Type', 'application/json')
            res.end(JSON.stringify({ error: { message: 'Google OAuth is not configured — set VITE_GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET' } }))
            return
          }

          let parsedBody: Record<string, unknown>
          try {
            parsedBody = JSON.parse(await readBody(req))
          } catch {
            res.statusCode = 400
            res.setHeader('Content-Type', 'application/json')
            res.end(JSON.stringify({ error: { message: 'Invalid JSON body' } }))
            return
          }

          const params = buildParams(parsedBody)
          if (!(params instanceof URLSearchParams)) {
            res.statusCode = 400
            res.setHeader('Content-Type', 'application/json')
            res.end(JSON.stringify({ error: { message: params.error } }))
            return
          }
          params.set('client_id', clientId)
          params.set('client_secret', clientSecret)

          let tokenResponse: Response
          try {
            tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: params,
            })
          } catch (err) {
            console.error(`[dev-google-oauth-proxy] could not reach Google (${path}):`, err)
            res.statusCode = 502
            res.setHeader('Content-Type', 'application/json')
            res.end(JSON.stringify({ error: { message: 'Dev proxy could not reach Google' } }))
            return
          }

          const text = await tokenResponse.text()
          res.statusCode = tokenResponse.status
          res.setHeader('Content-Type', 'application/json')
          res.end(text)
        })
      }

      register('/api/google-oauth-exchange', (body) =>
        typeof body.code === 'string' && typeof body.redirectUri === 'string'
          ? new URLSearchParams({ code: body.code, redirect_uri: body.redirectUri, grant_type: 'authorization_code' })
          : { error: 'Missing code or redirectUri' },
      )

      register('/api/google-oauth-refresh', (body) =>
        typeof body.refreshToken === 'string'
          ? new URLSearchParams({ refresh_token: body.refreshToken, grant_type: 'refresh_token' })
          : { error: 'Missing refreshToken' },
      )
    },
  }
}
