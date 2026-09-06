import { adfToMarkdown, type AdfNode } from './adf'
import type { JiraConnection } from './connection'

export type JiraIssue = {
  key: string
  summary: string
  status: string
  /** Jira's own bucket for a status — 'new' | 'indeterminate' | 'done' —
   *  used to color the status chip without hardcoding every possible
   *  workflow status name a Jira site could have. */
  statusCategory: string
  priorityName?: string
  priorityIconUrl?: string
  assigneeName?: string
  assigneeAvatarUrl?: string
  issueTypeName: string
  issueTypeIconUrl?: string
  projectName?: string
  updated?: string
  /** Read-only means the only "action" on an issue is jumping to the real
   *  thing in Jira. */
  url: string
}

export type JiraSearchResult = {
  issues: JiraIssue[]
  /** Cursor for the next page — absent/undefined means this was the last
   *  page. Jira's replacement search endpoint (/rest/api/3/search/jql, see
   *  api/jira-search.ts) dropped offset pagination entirely: no more
   *  startAt, and critically no more `total` in the response either, so
   *  there's no "X of Y" count to show — a cursor is all there is. */
  nextPageToken?: string
}

/** The full picture for one ticket — fetched separately from search results
 *  (which only carry the handful of fields listed in api/jira-search.ts),
 *  via api/jira-issue.ts when a ticket row is opened. */
export type JiraIssueDetail = JiraIssue & {
  descriptionMarkdown: string
  reporterName?: string
  reporterAvatarUrl?: string
  labels: string[]
  components: string[]
  fixVersions: string[]
  created?: string
  dueDate?: string
  resolutionName?: string
}

// Only the fields actually requested in api/jira-search.ts's `fields` list —
// Jira's real issue shape has dozens more, all irrelevant to a read-only list.
type JiraApiIssue = {
  key: string
  fields?: {
    summary?: string
    status?: { name?: string; statusCategory?: { key?: string } }
    priority?: { name?: string; iconUrl?: string }
    assignee?: { displayName?: string; avatarUrls?: { '24x24'?: string } }
    issuetype?: { name?: string; iconUrl?: string }
    project?: { name?: string }
    updated?: string
  }
}
type JiraApiSearchResponse = { issues?: JiraApiIssue[]; nextPageToken?: string }
type JiraApiError = { error?: { message?: string }; errorMessages?: string[] }

// Matches api/jira-issue.ts's DETAIL_FIELDS list.
type JiraApiIssueDetail = {
  key: string
  fields?: JiraApiIssue['fields'] & {
    description?: AdfNode | null
    reporter?: { displayName?: string; avatarUrls?: { '24x24'?: string } }
    labels?: string[]
    components?: { name?: string }[]
    fixVersions?: { name?: string }[]
    created?: string
    duedate?: string
    resolution?: { name?: string } | null
  }
}

function jiraErrorMessage(json: JiraApiError, status: number): string {
  if (typeof json.error?.message === 'string') return json.error.message
  if (Array.isArray(json.errorMessages) && json.errorMessages.length > 0) return json.errorMessages.join('; ')
  return `Jira error ${status}`
}

function toIssue(raw: JiraApiIssue, siteUrl: string): JiraIssue {
  const fields = raw.fields ?? {}
  return {
    key: raw.key,
    summary: fields.summary ?? '(no summary)',
    status: fields.status?.name ?? 'Unknown',
    statusCategory: fields.status?.statusCategory?.key ?? 'new',
    priorityName: fields.priority?.name,
    priorityIconUrl: fields.priority?.iconUrl,
    assigneeName: fields.assignee?.displayName,
    assigneeAvatarUrl: fields.assignee?.avatarUrls?.['24x24'],
    issueTypeName: fields.issuetype?.name ?? 'Issue',
    issueTypeIconUrl: fields.issuetype?.iconUrl,
    projectName: fields.project?.name,
    updated: fields.updated,
    url: `https://${siteUrl}/browse/${raw.key}`,
  }
}

/** The one call this whole feature makes — everything else (connection
 *  storage, the page) is plumbing around this. Goes through /api/jira-search
 *  (see its doc comment) rather than fetching atlassian.net directly, which
 *  a browser can't do anyway (CORS). */
export async function searchJiraIssues(connection: JiraConnection, jql: string, opts: { nextPageToken?: string; maxResults?: number } = {}): Promise<JiraSearchResult> {
  const response = await fetch('/api/jira-search', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      siteUrl: connection.siteUrl,
      email: connection.email,
      apiToken: connection.apiToken,
      jql,
      nextPageToken: opts.nextPageToken,
      maxResults: opts.maxResults,
    }),
  })
  const json = await response.json()
  if (!response.ok) throw new Error(jiraErrorMessage(json as JiraApiError, response.status))

  const parsed = json as JiraApiSearchResponse
  const issues = (parsed.issues ?? []).map((raw) => toIssue(raw, connection.siteUrl))
  return { issues, nextPageToken: parsed.nextPageToken }
}

/** Fetches everything about one ticket — used by JiraIssueDetailPanel when
 *  a row is opened, since search results only carry a handful of fields.
 *  Goes through /api/jira-issue (see its doc comment), same CORS reasoning
 *  as searchJiraIssues. */
export async function getJiraIssueDetail(connection: JiraConnection, issueKey: string): Promise<JiraIssueDetail> {
  const response = await fetch('/api/jira-issue', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ siteUrl: connection.siteUrl, email: connection.email, apiToken: connection.apiToken, issueKey }),
  })
  const json = await response.json()
  if (!response.ok) throw new Error(jiraErrorMessage(json as JiraApiError, response.status))

  const raw = json as JiraApiIssueDetail
  const fields = raw.fields ?? {}
  return {
    ...toIssue(raw, connection.siteUrl),
    descriptionMarkdown: adfToMarkdown(fields.description),
    reporterName: fields.reporter?.displayName,
    reporterAvatarUrl: fields.reporter?.avatarUrls?.['24x24'],
    labels: fields.labels ?? [],
    components: (fields.components ?? []).map((c) => c.name).filter((name): name is string => Boolean(name)),
    fixVersions: (fields.fixVersions ?? []).map((v) => v.name).filter((name): name is string => Boolean(name)),
    created: fields.created,
    dueDate: fields.duedate,
    resolutionName: fields.resolution?.name,
  }
}

/** Resolves the connected account's own Jira accountId — needed to build a
 *  "ever assigned to me" JQL query (see buildEverAssignedToMeJql below).
 *  Goes through /api/jira-myself, same CORS reasoning as the other calls. */
export async function getJiraMyself(connection: JiraConnection): Promise<{ accountId: string; displayName?: string }> {
  const response = await fetch('/api/jira-myself', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ siteUrl: connection.siteUrl, email: connection.email, apiToken: connection.apiToken }),
  })
  const json = await response.json()
  if (!response.ok) throw new Error(jiraErrorMessage(json as JiraApiError, response.status))

  const parsed = json as { accountId?: string; displayName?: string }
  if (!parsed.accountId) throw new Error("Jira didn't return an account ID for this user")
  return { accountId: parsed.accountId, displayName: parsed.displayName }
}

/** JQL's historical `WAS` operator — the only way to match "was ever
 *  assigned," not just "is currently assigned" — flatly rejects the
 *  currentUser() function (confirmed against Atlassian's own JQL docs: it
 *  throws "A value provided by the function 'currentUser' is invalid for
 *  the field 'assignee'"). An explicit accountId works fine with WAS, so
 *  this needs a resolved accountId (getJiraMyself) rather than the
 *  currentUser() shorthand every other query in this app can just use. */
export function buildEverAssignedToMeJql(accountId: string): string {
  return `(assignee = "${accountId}" OR assignee WAS "${accountId}") ORDER BY updated DESC`
}
