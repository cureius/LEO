export const config = { runtime: 'edge' }

// Same CORS/no-shared-secret reasoning as api/jira-search.ts.
const SITE_URL_PATTERN = /^[a-z0-9-]+\.atlassian\.net$/i
// Jira issue keys are always PROJECTKEY-NUMBER (e.g. "ABJ-102") — validated
// before being interpolated into the request path so a malformed value
// can't smuggle extra path segments into the upstream request.
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

type JiraIssueRequest = {
  siteUrl?: string
  email?: string
  apiToken?: string
  issueKey?: string
}

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: { message } }), { status, headers: { 'Content-Type': 'application/json' } })
}

export default async function handler(req: Request): Promise<Response> {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  let body: JiraIssueRequest
  try {
    body = await req.json()
  } catch {
    return jsonError('Invalid JSON body', 400)
  }

  const { siteUrl, email, apiToken, issueKey } = body
  if (!siteUrl || !email || !apiToken || !issueKey) {
    return jsonError('Missing siteUrl, email, apiToken, or issueKey', 400)
  }
  if (!SITE_URL_PATTERN.test(siteUrl)) {
    return jsonError('siteUrl must be a bare Atlassian Cloud host, e.g. "yourteam.atlassian.net"', 400)
  }
  if (!ISSUE_KEY_PATTERN.test(issueKey)) {
    return jsonError('issueKey must look like PROJECT-123', 400)
  }

  const basicAuth = btoa(`${email}:${apiToken}`)
  const url = `https://${siteUrl}/rest/api/3/issue/${encodeURIComponent(issueKey)}?fields=${DETAIL_FIELDS.join(',')}`
  let jiraResponse: Response
  try {
    jiraResponse = await fetch(url, {
      headers: { Accept: 'application/json', Authorization: `Basic ${basicAuth}` },
    })
  } catch {
    return jsonError('Could not reach Jira — check the site URL', 502)
  }

  const text = await jiraResponse.text()
  return new Response(text, { status: jiraResponse.status, headers: { 'Content-Type': 'application/json' } })
}
