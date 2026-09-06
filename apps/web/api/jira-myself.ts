export const config = { runtime: 'edge' }

// Same CORS/no-shared-secret reasoning as api/jira-search.ts.
const SITE_URL_PATTERN = /^[a-z0-9-]+\.atlassian\.net$/i

type JiraMyselfRequest = {
  siteUrl?: string
  email?: string
  apiToken?: string
}

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: { message } }), { status, headers: { 'Content-Type': 'application/json' } })
}

/** Resolves the connected account's Jira accountId — needed because JQL's
 *  historical `WAS` operator (see jira/api.ts's buildEverAssignedJql doc
 *  comment) rejects the currentUser() function outright and requires an
 *  explicit accountId instead. */
export default async function handler(req: Request): Promise<Response> {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  let body: JiraMyselfRequest
  try {
    body = await req.json()
  } catch {
    return jsonError('Invalid JSON body', 400)
  }

  const { siteUrl, email, apiToken } = body
  if (!siteUrl || !email || !apiToken) {
    return jsonError('Missing siteUrl, email, or apiToken', 400)
  }
  if (!SITE_URL_PATTERN.test(siteUrl)) {
    return jsonError('siteUrl must be a bare Atlassian Cloud host, e.g. "yourteam.atlassian.net"', 400)
  }

  const basicAuth = btoa(`${email}:${apiToken}`)
  let jiraResponse: Response
  try {
    jiraResponse = await fetch(`https://${siteUrl}/rest/api/3/myself`, {
      headers: { Accept: 'application/json', Authorization: `Basic ${basicAuth}` },
    })
  } catch {
    return jsonError('Could not reach Jira — check the site URL', 502)
  }

  const text = await jiraResponse.text()
  return new Response(text, { status: jiraResponse.status, headers: { 'Content-Type': 'application/json' } })
}
