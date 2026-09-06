import type { Plugin, ViteDevServer } from 'vite'

/**
 * Dev-only stand-in for api/jira-search.ts, api/jira-issue.ts, and
 * api/jira-myself.ts — same reasoning as devGoogleOAuthProxyPlugin.ts:
 * Vite's dev server doesn't run `api/*.ts` as serverless functions, only
 * Vercel does, so without this the Jira page 404s under plain `pnpm dev`.
 * No env vars to load here (unlike Google's proxy) since there's no shared
 * app secret — every credential in the request body is the end user's own.
 */
function readBody(req: import('http').IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = []
    req.on('data', (chunk) => chunks.push(chunk))
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')))
    req.on('error', reject)
  })
}

const SITE_URL_PATTERN = /^[a-z0-9-]+\.atlassian\.net$/i
const ISSUE_KEY_PATTERN = /^[A-Z][A-Z0-9_]*-\d+$/i
const DETAIL_FIELDS = [
  'summary',
  'description',
  'status',
  'priority',
  'assignee',
  'reporter',
  'issuetype',
  'project',
  'labels',
  'components',
  'fixVersions',
  'created',
  'updated',
  'duedate',
  'resolution',
]

type JsonBody = Record<string, unknown>

/** Shared shape all three routes need: read the body, check required
 *  fields + the siteUrl pattern, build the upstream Jira request, forward
 *  its response verbatim. `buildRequest` returns either the upstream
 *  request or an error message for a field it alone knows how to validate
 *  (e.g. jira-issue's issueKey format). */
function registerJiraProxy(
  server: ViteDevServer,
  path: string,
  requiredFields: string[],
  buildRequest: (body: JsonBody, basicAuth: string) => { url: string; init?: RequestInit } | { error: string },
) {
  server.middlewares.use(path, async (req, res) => {
    const respond = (status: number, data: unknown) => {
      res.statusCode = status
      res.setHeader('Content-Type', 'application/json')
      res.end(typeof data === 'string' ? data : JSON.stringify(data))
    }

    if (req.method !== 'POST') {
      res.statusCode = 405
      res.end('Method not allowed')
      return
    }

    let body: JsonBody
    try {
      body = JSON.parse(await readBody(req))
    } catch {
      respond(400, { error: { message: 'Invalid JSON body' } })
      return
    }

    const missing = requiredFields.filter((field) => !body[field])
    if (missing.length > 0) {
      respond(400, { error: { message: `Missing ${missing.join(', ')}` } })
      return
    }
    const siteUrl = body.siteUrl
    if (typeof siteUrl !== 'string' || !SITE_URL_PATTERN.test(siteUrl)) {
      respond(400, { error: { message: 'siteUrl must be a bare Atlassian Cloud host, e.g. "yourteam.atlassian.net"' } })
      return
    }

    const basicAuth = Buffer.from(`${body.email}:${body.apiToken}`).toString('base64')
    const built = buildRequest(body, basicAuth)
    if ('error' in built) {
      respond(400, { error: { message: built.error } })
      return
    }

    let jiraResponse: Response
    try {
      jiraResponse = await fetch(built.url, built.init)
    } catch (err) {
      console.error(`[dev-jira-proxy] could not reach Jira (${path}):`, err)
      respond(502, { error: { message: 'Dev proxy could not reach Jira — check the site URL' } })
      return
    }

    const text = await jiraResponse.text()
    respond(jiraResponse.status, text)
  })
}

export function devJiraProxyPlugin(): Plugin {
  return {
    name: 'dev-jira-proxy',
    configureServer(server) {
      registerJiraProxy(server, '/api/jira-search', ['siteUrl', 'email', 'apiToken', 'jql'], (body, basicAuth) => ({
        // /rest/api/3/search was removed by Atlassian — see
        // api/jira-search.ts's doc comment for the pagination shape change
        // this forces (nextPageToken cursor, no more startAt/total).
        url: `https://${body.siteUrl}/rest/api/3/search/jql`,
        init: {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Accept: 'application/json', Authorization: `Basic ${basicAuth}` },
          body: JSON.stringify({
            jql: body.jql,
            maxResults: Math.min(typeof body.maxResults === 'number' ? body.maxResults : 50, 100),
            fields: ['summary', 'status', 'priority', 'assignee', 'issuetype', 'updated', 'project'],
            ...(body.nextPageToken ? { nextPageToken: body.nextPageToken } : {}),
          }),
        },
      }))

      registerJiraProxy(server, '/api/jira-issue', ['siteUrl', 'email', 'apiToken', 'issueKey'], (body, basicAuth) => {
        const issueKey = body.issueKey
        if (typeof issueKey !== 'string' || !ISSUE_KEY_PATTERN.test(issueKey)) return { error: 'issueKey must look like PROJECT-123' }
        return {
          url: `https://${body.siteUrl}/rest/api/3/issue/${encodeURIComponent(issueKey)}?fields=${DETAIL_FIELDS.join(',')}`,
          init: { headers: { Accept: 'application/json', Authorization: `Basic ${basicAuth}` } },
        }
      })

      registerJiraProxy(server, '/api/jira-myself', ['siteUrl', 'email', 'apiToken'], (body, basicAuth) => ({
        url: `https://${body.siteUrl}/rest/api/3/myself`,
        init: { headers: { Accept: 'application/json', Authorization: `Basic ${basicAuth}` } },
      }))
    },
  }
}
