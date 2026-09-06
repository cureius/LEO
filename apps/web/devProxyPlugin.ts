import type { Plugin } from 'vite'

/**
 * Dev-only stand-in for api/claude.ts's Vercel Edge Function. Vite's dev
 * server has no concept of `api/*.ts` as serverless functions — that only
 * exists once deployed to Vercel (or under `vercel dev`, not installed in
 * this environment) — so without this, `/api/claude` 404s under plain
 * `pnpm dev` and the entire AI chat feature is unreachable locally, not
 * just untested. Same forwarding logic as the real Edge Function, adapted
 * from the Fetch API (Request/Response) to Vite's Node http req/res
 * middleware API — api/claude.ts remains the source of truth for what
 * actually deploys; this just makes local dev work too.
 */
export function devClaudeProxyPlugin(): Plugin {
  return {
    name: 'dev-claude-proxy',
    configureServer(server) {
      server.middlewares.use('/api/claude', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405
          res.end('Method not allowed')
          return
        }

        const apiKey = req.headers['x-api-key']
        if (!apiKey || typeof apiKey !== 'string') {
          res.statusCode = 401
          res.setHeader('Content-Type', 'application/json')
          res.end(JSON.stringify({ error: { message: 'Missing x-api-key header' } }))
          return
        }

        let body: Buffer
        try {
          const chunks: Buffer[] = []
          for await (const chunk of req) chunks.push(chunk as Buffer)
          body = Buffer.concat(chunks)
        } catch (err) {
          // Same hang-forever class of bug as below — now more reachable
          // than it used to be: a PDF attachment can put several MB of
          // base64 into this request body, giving a dropped connection more
          // opportunity to interrupt the upload mid-read.
          console.error('[dev-claude-proxy] failed reading the request body:', err)
          res.statusCode = 400
          res.end()
          return
        }

        // This whole handler had NO error handling at all — if fetch() threw
        // for any reason (DNS failure, connection reset, TLS error, anything
        // on this machine's path to Anthropic), the rejection became an
        // unhandled promise rejection: Vite's Connect-based middleware stack
        // does not catch that automatically, so res.end() was simply never
        // called and the browser's request hung until ITS OWN client-side
        // idle timeout eventually fired — no matter how long that timeout was
        // set to, since the real failure already happened, silently, near
        // the very start. Reported live as "no data for 75s" even right
        // after raising that timeout from 30s specifically because the
        // timeout was never the bottleneck.
        let anthropicResponse: Response
        try {
          anthropicResponse = await fetch('https://api.anthropic.com/v1/messages', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': (req.headers['anthropic-version'] as string) ?? '2023-06-01',
              'anthropic-beta': (req.headers['anthropic-beta'] as string) ?? '',
            },
            body,
          })
        } catch (err) {
          const message = err instanceof Error ? err.message : String(err)
          console.error('[dev-claude-proxy] could not reach Anthropic:', err)
          res.statusCode = 502
          res.setHeader('Content-Type', 'application/json')
          res.end(JSON.stringify({ error: { message: `Dev proxy could not reach Anthropic: ${message}` } }))
          return
        }

        res.statusCode = anthropicResponse.status
        // Allowlist, not a blocklist — forwarding every upstream header
        // verbatim onto a raw Node `http.ServerResponse` is generally bad
        // practice regardless of whether it's the cause of any specific bug.
        // `content-encoding`/`content-length` were already confirmed-bad
        // (fetch() transparently decompresses gzip, but those headers still
        // describe the ORIGINAL compressed bytes, so forwarding them made the
        // browser try to gunzip plain JSON and fail with
        // ERR_CONTENT_DECODING_FAILED). `transfer-encoding` was investigated
        // as a theory for a separate live streaming issue (a header vs.
        // actual-bytes mismatch on a raw Node response) and directly disproven
        // via a local repro server — Node's `http.ServerResponse` produced a
        // byte-identical, uncorrupted stream either way — so that was NOT the
        // cause. Left as an allowlist anyway since only content-type is
        // actually needed for the browser to interpret the body correctly.
        const contentType = anthropicResponse.headers.get('content-type')
        if (contentType) res.setHeader('content-type', contentType)

        if (!anthropicResponse.body) {
          res.end()
          return
        }
        const reader = anthropicResponse.body.getReader()
        try {
          while (true) {
            const { done, value } = await reader.read()
            if (done) break
            res.write(value)
          }
        } catch (err) {
          // Same class of bug as the fetch() above, mid-stream instead of at
          // the start — a dropped connection partway through would otherwise
          // also hang forever instead of ending the response. Status/headers
          // are already flushed by this point, so there's no way to send a
          // fresh error body — ending the response is the best this can do,
          // which at least lets the browser's reader see `done: true` instead
          // of waiting on bytes that will never arrive.
          console.error('[dev-claude-proxy] stream from Anthropic broke mid-response:', err)
        }
        res.end()
      })
    },
  }
}
