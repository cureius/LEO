export const config = { runtime: 'edge' }

// Atlassian Cloud's REST API doesn't send CORS headers permitting a
// third-party origin, so a direct browser fetch from this app to
// `https://<site>.atlassian.net/...` is blocked regardless of credentials —
// same reason Google Calendar's token exchange needs api/google-oauth-*.ts.
// Unlike Google, there's no shared app secret to protect here (the API
// token is the end user's own personal credential, not this app's OAuth
// client secret) — this proxy exists purely to get around CORS, not to hide
// a secret from the browser.
const SITE_URL_PATTERN = /^[a-z0-9-]+\.atlassian\.net$/i

type JiraSearchRequest = {
  siteUrl?: string
  email?: string
  apiToken?: string
  jql?: string
  nextPageToken?: string
  maxResults?: number
}

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: { message } }), { status, headers: { 'Content-Type': 'application/json' } })
}

export default async function handler(req: Request): Promise<Response> {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  let body: JiraSearchRequest
  try {
    body = await req.json()
  } catch {
    return jsonError('Invalid JSON body', 400)
  }

  const { siteUrl, email, apiToken, jql } = body
  if (!siteUrl || !email || !apiToken || !jql) {
    return jsonError('Missing siteUrl, email, apiToken, or jql', 400)
  }
  // Rejects anything that isn't a bare Atlassian Cloud host — without this,
  // a caller could point siteUrl at an arbitrary host and turn this into an
  // open server-side fetch proxy (SSRF), since everything else in the body
  // is attacker-controlled too.
  if (!SITE_URL_PATTERN.test(siteUrl)) {
    return jsonError('siteUrl must be a bare Atlassian Cloud host, e.g. "yourteam.atlassian.net"', 400)
  }

  const basicAuth = btoa(`${email}:${apiToken}`)
  let jiraResponse: Response
  try {
    // /rest/api/3/search was fully removed by Atlassian (confirmed live —
    // it now 410s with a pointer to this replacement). The new endpoint
    // drops offset pagination entirely: no startAt, no total in the
    // response — only a cursor (nextPageToken), present unless this is the
    // last page. See jira/api.ts's JiraSearchResult for how the client
    // handles "unknown total" as a result of this.
    jiraResponse = await fetch(`https://${siteUrl}/rest/api/3/search/jql`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        Authorization: `Basic ${basicAuth}`,
      },
      body: JSON.stringify({
        jql,
        maxResults: Math.min(body.maxResults ?? 50, 100),
        fields: ['summary', 'status', 'priority', 'assignee', 'issuetype', 'updated', 'project'],
        ...(body.nextPageToken ? { nextPageToken: body.nextPageToken } : {}),
      }),
    })
  } catch {
    return jsonError('Could not reach Jira — check the site URL', 502)
  }

  const text = await jiraResponse.text()
  return new Response(text, { status: jiraResponse.status, headers: { 'Content-Type': 'application/json' } })
}
