import { useEffect, useMemo, useState, type FormEvent } from 'react'
import { ArrowDown, ArrowUp, ArrowUpDown, ExternalLink, History, RefreshCw, Ticket } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { TextField } from '@/components/ui/TextField'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { JiraIssueDetailPanel } from '@/components/jira/JiraIssueDetailPanel'
import { getJiraConnection, saveJiraConnection, disconnectJira, normalizeSiteUrl, type JiraConnection } from '@/jira/connection'
import { searchJiraIssues, getJiraMyself, buildEverAssignedToMeJql, type JiraIssue } from '@/jira/api'
import { cn } from '@/lib/utils'

const ALL = '__all__'
type SortField = 'key' | 'summary' | 'status' | 'issueTypeName' | 'priorityName' | 'assigneeName' | 'updated'
type SortDir = 'asc' | 'desc'

const DEFAULT_JQL = 'assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC'
const PAGE_SIZE = 50

function statusBadgeClasses(category: string): string {
  if (category === 'done') return 'bg-success/15 text-success'
  if (category === 'indeterminate') return 'bg-accent-muted text-accent'
  return 'bg-surface-elevated text-text-secondary'
}

function formatUpdated(iso?: string): string {
  if (!iso) return ''
  const d = new Date(iso)
  const diffMin = Math.round((Date.now() - d.getTime()) / 60_000)
  if (diffMin < 60) return `${Math.max(diffMin, 0)}m ago`
  const diffHr = Math.round(diffMin / 60)
  if (diffHr < 24) return `${diffHr}h ago`
  const diffDay = Math.round(diffHr / 24)
  if (diffDay < 30) return `${diffDay}d ago`
  return d.toLocaleDateString()
}

/** Shown when there's no stored connection yet. Validates the credentials
 *  with a real (tiny) Jira search BEFORE persisting anything — a bad
 *  site/email/token otherwise wouldn't surface until the page's very first
 *  load after a reload, which reads as "it silently didn't work." */
function ConnectForm({ onConnected }: { onConnected: (c: JiraConnection) => void }) {
  const [siteUrl, setSiteUrl] = useState('')
  const [email, setEmail] = useState('')
  const [apiToken, setApiToken] = useState('')
  const [connecting, setConnecting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setConnecting(true)
    setError(null)
    const connection: JiraConnection = { siteUrl: normalizeSiteUrl(siteUrl), email: email.trim(), apiToken: apiToken.trim() }
    try {
      await searchJiraIssues(connection, DEFAULT_JQL, { maxResults: 1 })
      await saveJiraConnection(connection)
      onConnected(connection)
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    } finally {
      setConnecting(false)
    }
  }

  return (
    <div className="max-w-md rounded-leo-md border border-divider bg-surface p-4">
      <h2 className="mb-1 text-sm font-semibold text-text-primary">Connect Jira</h2>
      <p className="mb-3 text-xs text-text-secondary">
        Read-only — LEO only ever reads issues here, nothing is written back to Jira. Needs a personal{' '}
        <a href="https://id.atlassian.com/manage-profile/security/api-tokens" target="_blank" rel="noreferrer" className="text-accent hover:underline">
          API token
        </a>{' '}
        (~1 minute to generate).
      </p>
      <form onSubmit={(e) => void handleSubmit(e)} className="flex flex-col gap-3">
        <TextField label="Jira site" placeholder="yourteam.atlassian.net" value={siteUrl} onChange={(e) => setSiteUrl(e.target.value)} required />
        <TextField label="Atlassian account email" type="email" placeholder="you@company.com" value={email} onChange={(e) => setEmail(e.target.value)} required />
        <TextField label="API token" type="password" value={apiToken} onChange={(e) => setApiToken(e.target.value)} required />
        {error && <p className="text-xs text-danger">{error}</p>}
        <Button type="submit" disabled={connecting || !siteUrl.trim() || !email.trim() || !apiToken.trim()}>
          {connecting ? 'Connecting…' : 'Connect'}
        </Button>
      </form>
    </div>
  )
}

/** Clicking the row opens the in-app detail panel (full description,
 *  reporter, labels, components — everything the search list's handful of
 *  fields can't show); the trailing external-link icon is a separate
 *  target for jumping straight to Jira instead, since those are two
 *  genuinely different intents. */
function IssueRow({ issue, rowNumber, onOpen }: { issue: JiraIssue; rowNumber: number; onOpen: () => void }) {
  return (
    <tr role="button" tabIndex={0} onClick={onOpen} onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onOpen() } }} className="cursor-pointer border-b border-divider transition-colors last:border-b-0 hover:bg-surface-elevated">
      <td className="px-3 py-2 text-xs text-text-secondary tabular-nums">{rowNumber}</td>
      <td className="px-3 py-2 text-sm font-medium whitespace-nowrap text-text-secondary">{issue.key}</td>
      <td className="min-w-[200px] px-3 py-2 text-sm text-text-primary">
        <span className="line-clamp-2">{issue.summary}</span>
      </td>
      <td className="px-3 py-2 whitespace-nowrap">
        <span className="flex items-center gap-1.5 text-sm text-text-primary">
          {issue.issueTypeIconUrl && <img src={issue.issueTypeIconUrl} alt="" className="h-4 w-4 shrink-0" />}
          {issue.issueTypeName}
        </span>
      </td>
      <td className="px-3 py-2 whitespace-nowrap">
        <span className={cn('inline-block rounded-leo-pill px-2 py-0.5 text-xs font-medium', statusBadgeClasses(issue.statusCategory))}>{issue.status}</span>
      </td>
      <td className="px-3 py-2 whitespace-nowrap">
        <span className="flex items-center gap-1.5 text-sm text-text-primary">
          {issue.priorityIconUrl && <img src={issue.priorityIconUrl} alt="" className="h-4 w-4 shrink-0" />}
          {issue.priorityName ?? '—'}
        </span>
      </td>
      <td className="px-3 py-2 text-sm whitespace-nowrap text-text-secondary">{issue.assigneeName ?? 'Unassigned'}</td>
      <td className="px-3 py-2 text-sm whitespace-nowrap text-text-secondary">{issue.updated ? formatUpdated(issue.updated) : '—'}</td>
      <td className="px-3 py-2 text-right">
        <a
          href={issue.url}
          target="_blank"
          rel="noreferrer"
          onClick={(e) => e.stopPropagation()}
          aria-label={`Open ${issue.key} in Jira`}
          className="inline-block shrink-0 rounded-leo-sm p-0.5 text-text-secondary hover:bg-surface-elevated hover:text-text-primary"
        >
          <ExternalLink className="h-3.5 w-3.5" aria-hidden="true" />
        </a>
      </td>
    </tr>
  )
}

function SortHeader({ label, field, sortField, sortDir, onSort }: { label: string; field: SortField; sortField: SortField; sortDir: SortDir; onSort: (field: SortField) => void }) {
  const active = sortField === field
  const Icon = active ? (sortDir === 'asc' ? ArrowUp : ArrowDown) : ArrowUpDown
  return (
    <th className="px-3 py-2 text-left text-xs font-medium tracking-wide text-text-secondary uppercase select-none">
      <button type="button" onClick={() => onSort(field)} className={cn('flex items-center gap-1 hover:text-text-primary', active && 'text-text-primary')}>
        {label}
        <Icon className="h-3 w-3" aria-hidden="true" />
      </button>
    </th>
  )
}

function FilterSelect({ label, value, options, onChange }: { label: string; value: string; options: string[]; onChange: (v: string) => void }) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger size="sm" className="min-w-[130px]">
        <SelectValue placeholder={label} />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value={ALL}>All {label.toLowerCase()}</SelectItem>
        {options.map((o) => (
          <SelectItem key={o} value={o}>
            {o}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}

/**
 * Read-only, one-way Jira ticket browser — a dedicated page rather than
 * mixing issues into Today/Inbox/Projects, since these aren't LEO items
 * (nothing here goes through the sync engine, nothing is ever written back
 * to Jira). See jira/connection.ts and api/jira-search.ts for the
 * connection/proxy this depends on.
 */
export function JiraPage() {
  const [connection, setConnection] = useState<JiraConnection | null | 'loading'>('loading')
  const [jql, setJql] = useState(DEFAULT_JQL)
  const [issues, setIssues] = useState<JiraIssue[]>([])
  const [openIssueKey, setOpenIssueKey] = useState<string | null>(null)
  // Jira's search endpoint dropped `total` entirely (see jira/api.ts) —
  // undefined means "no more pages," not "unknown count."
  const [nextPageToken, setNextPageToken] = useState<string | undefined>(undefined)
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [statusFilter, setStatusFilter] = useState(ALL)
  const [typeFilter, setTypeFilter] = useState(ALL)
  const [priorityFilter, setPriorityFilter] = useState(ALL)
  const [sortField, setSortField] = useState<SortField>('updated')
  const [sortDir, setSortDir] = useState<SortDir>('desc')

  function handleSort(field: SortField) {
    if (field === sortField) {
      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'))
    } else {
      setSortField(field)
      setSortDir('asc')
    }
  }

  const statusOptions = useMemo(() => Array.from(new Set(issues.map((i) => i.status))).sort(), [issues])
  const typeOptions = useMemo(() => Array.from(new Set(issues.map((i) => i.issueTypeName))).sort(), [issues])
  const priorityOptions = useMemo(() => Array.from(new Set(issues.map((i) => i.priorityName).filter((p): p is string => !!p))).sort(), [issues])

  const visibleIssues = useMemo(() => {
    const filtered = issues.filter(
      (i) =>
        (statusFilter === ALL || i.status === statusFilter) &&
        (typeFilter === ALL || i.issueTypeName === typeFilter) &&
        (priorityFilter === ALL || i.priorityName === priorityFilter),
    )
    const dir = sortDir === 'asc' ? 1 : -1
    return [...filtered].sort((a, b) => {
      const av = a[sortField] ?? ''
      const bv = b[sortField] ?? ''
      return av < bv ? -dir : av > bv ? dir : 0
    })
  }, [issues, statusFilter, typeFilter, priorityFilter, sortField, sortDir])

  useEffect(() => {
    getJiraConnection()
      .then(setConnection)
      .catch(() => setConnection(null))
  }, [])

  /** No `pageToken` arg = fresh search (replaces the list); passing the
   *  current nextPageToken appends instead — same shape as the old
   *  startAt-based version, just keyed off a cursor instead of an offset. */
  async function runSearch(target: JiraConnection, query: string, pageToken?: string) {
    setLoading(true)
    setLoadError(null)
    try {
      const result = await searchJiraIssues(target, query, { nextPageToken: pageToken, maxResults: PAGE_SIZE })
      setIssues((prev) => (pageToken ? [...prev, ...result.issues] : result.issues))
      setNextPageToken(result.nextPageToken)
      if (!pageToken) {
        setStatusFilter(ALL)
        setTypeFilter(ALL)
        setPriorityFilter(ALL)
      }
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : String(err))
    } finally {
      setLoading(false)
    }
  }

  // Covers both "a stored connection just loaded on mount" and "the user
  // just connected for the first time" — both are just `connection` going
  // from null/'loading' to a real value, so one effect handles the initial
  // search for either case. handleConnected deliberately does NOT also call
  // runSearch itself — this effect already will, once `connection` updates,
  // and doing both would fire the search twice on a fresh connect.
  useEffect(() => {
    if (connection && connection !== 'loading') void runSearch(connection, jql)
    // Deliberately NOT re-running on `jql` edits — that's what Search is for.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [connection])

  /** JQL's historical WAS operator can't take currentUser() (see
   *  buildEverAssignedToMeJql's doc comment) — resolves the real accountId
   *  first, then runs the query built from it. */
  async function handleEverAssignedToMe() {
    if (!connection || connection === 'loading') return
    setLoading(true)
    setLoadError(null)
    try {
      const me = await getJiraMyself(connection)
      const query = buildEverAssignedToMeJql(me.accountId)
      setJql(query)
      await runSearch(connection, query)
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : String(err))
    } finally {
      setLoading(false)
    }
  }

  function handleConnected(newConnection: JiraConnection) {
    setIssues([])
    setNextPageToken(undefined)
    setConnection(newConnection)
  }

  async function handleDisconnect() {
    await disconnectJira()
    setConnection(null)
    setIssues([])
    setNextPageToken(undefined)
  }

  return (
    <div className="p-6">
      <div className="mb-1 flex items-center justify-between">
        <h1 className="text-xl font-semibold text-text-primary">Jira</h1>
        {connection && connection !== 'loading' && (
          <Button variant="ghost" size="sm" onClick={() => void handleDisconnect()} className="text-text-secondary">
            Disconnect
          </Button>
        )}
      </div>
      <p className="mb-4 text-sm text-text-secondary">Read-only view of your Jira tickets — nothing here is ever written back.</p>

      {connection === 'loading' && <p className="text-sm text-text-secondary">Loading…</p>}

      {connection === null && <ConnectForm onConnected={handleConnected} />}

      {connection && connection !== 'loading' && (
        <div className="flex flex-col gap-3">
          <form
            onSubmit={(e) => {
              e.preventDefault()
              void runSearch(connection, jql)
            }}
            className="flex items-end gap-2"
          >
            <TextField
              label="JQL"
              className="min-w-[240px] flex-1"
              inputClassName="font-mono text-xs"
              value={jql}
              onChange={(e) => setJql(e.target.value)}
            />
            <Button type="submit" variant="outline" disabled={loading} className="gap-1.5">
              <RefreshCw className={cn('h-3.5 w-3.5', loading && 'animate-spin')} aria-hidden="true" />
              {loading ? 'Searching…' : 'Search'}
            </Button>
            <Button
              type="button"
              variant="outline"
              onClick={() => void handleEverAssignedToMe()}
              disabled={loading}
              className="gap-1.5"
              title="Finds tickets you're assigned to now, plus ones you used to be assigned before they moved on — not just your current assignments."
            >
              <History className="h-3.5 w-3.5" aria-hidden="true" />
              Ever assigned to me
            </Button>
          </form>

          {loadError && <p className="text-sm text-danger">{loadError}</p>}

          {!loading && issues.length === 0 && !loadError && (
            <p className="flex items-center gap-1.5 text-sm text-text-secondary">
              <Ticket className="h-3.5 w-3.5" aria-hidden="true" />
              No issues match this query.
            </p>
          )}

          {issues.length > 0 && (
            <>
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-sm text-text-secondary">
                  {visibleIssues.length === issues.length ? `${issues.length} ticket${issues.length === 1 ? '' : 's'}` : `${visibleIssues.length} of ${issues.length} tickets`}
                </span>
                <FilterSelect label="Status" value={statusFilter} options={statusOptions} onChange={setStatusFilter} />
                <FilterSelect label="Type" value={typeFilter} options={typeOptions} onChange={setTypeFilter} />
                <FilterSelect label="Priority" value={priorityFilter} options={priorityOptions} onChange={setPriorityFilter} />
              </div>

              <div className="overflow-x-auto rounded-leo-md border border-divider bg-surface">
                <table className="w-full border-collapse">
                  <thead>
                    <tr className="border-b border-divider">
                      <th className="px-3 py-2 text-left text-xs font-medium tracking-wide text-text-secondary uppercase">#</th>
                      <SortHeader label="Key" field="key" sortField={sortField} sortDir={sortDir} onSort={handleSort} />
                      <SortHeader label="Summary" field="summary" sortField={sortField} sortDir={sortDir} onSort={handleSort} />
                      <SortHeader label="Type" field="issueTypeName" sortField={sortField} sortDir={sortDir} onSort={handleSort} />
                      <SortHeader label="Status" field="status" sortField={sortField} sortDir={sortDir} onSort={handleSort} />
                      <SortHeader label="Priority" field="priorityName" sortField={sortField} sortDir={sortDir} onSort={handleSort} />
                      <SortHeader label="Assignee" field="assigneeName" sortField={sortField} sortDir={sortDir} onSort={handleSort} />
                      <SortHeader label="Updated" field="updated" sortField={sortField} sortDir={sortDir} onSort={handleSort} />
                      <th className="px-3 py-2" />
                    </tr>
                  </thead>
                  <tbody>
                    {visibleIssues.map((issue, i) => (
                      <IssueRow key={issue.key} issue={issue} rowNumber={i + 1} onOpen={() => setOpenIssueKey(issue.key)} />
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}

          {nextPageToken && (
            <Button variant="outline" size="sm" onClick={() => void runSearch(connection, jql, nextPageToken)} disabled={loading} className="self-start">
              {loading ? 'Loading…' : `Load more (${issues.length} so far)`}
            </Button>
          )}
        </div>
      )}

      {openIssueKey && connection && connection !== 'loading' && (
        <JiraIssueDetailPanel connection={connection} issueKey={openIssueKey} onClose={() => setOpenIssueKey(null)} />
      )}
    </div>
  )
}
