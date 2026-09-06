export const config = { runtime: 'edge' }

/**
 * Same-origin proxy for the Anthropic Messages API. Not a "hide the key"
 * measure — the key is visible in the browser's own DevTools the moment the
 * user submits it, proxy or not, since this is a BYOK feature by design
 * (matches the native app's Keychain-stored key, just less secure at rest,
 * which is a real and disclosed limitation of a browser, not something this
 * proxy can fix). What it actually buys: no Anthropic
 * "dangerous-direct-browser-access" opt-in UX for a feature that's already
 * a trust ask, room for server-side rate-limiting/logging without ever
 * persisting the key, and no dependency on Anthropic's CORS policy.
 *
 * A pure byte passthrough — streaming or not, this never inspects the body.
 *
 * One real exception to "never inspects": `content-encoding`/`content-length`
 * are stripped from the forwarded headers. `fetch()` transparently
 * decompresses a gzip'd upstream response, but those two headers still
 * describe the ORIGINAL compressed bytes — forwarding them verbatim
 * alongside the now-decompressed body makes the browser try to gunzip
 * plain JSON and fail with ERR_CONTENT_DECODING_FAILED. Caught live in the
 * dev-server equivalent of this proxy (devProxyPlugin.ts) — curl didn't
 * trigger it (no gzip negotiated without `Accept-Encoding`), but a real
 * browser does send that header, so this bites in practice, not just in
 * theory.
 */
export default async function handler(req: Request): Promise<Response> {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  const apiKey = req.headers.get('x-api-key')
  if (!apiKey) {
    return new Response(JSON.stringify({ error: { message: 'Missing x-api-key header' } }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  const anthropicResponse = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': req.headers.get('anthropic-version') ?? '2023-06-01',
      'anthropic-beta': req.headers.get('anthropic-beta') ?? '',
    },
    body: req.body,
    // @ts-expect-error -- `duplex` is required by undici for streaming request
    // bodies but isn't yet in the standard fetch() TypeScript lib types.
    duplex: 'half',
  })

  const headers = new Headers(anthropicResponse.headers)
  headers.delete('content-encoding')
  headers.delete('content-length')

  return new Response(anthropicResponse.body, {
    status: anthropicResponse.status,
    headers,
  })
}
