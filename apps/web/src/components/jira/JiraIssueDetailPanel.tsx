import { useEffect, useState } from 'react'
import * as Dialog from '@radix-ui/react-dialog'
import { ExternalLink, X } from 'lucide-react'
import { Markdown } from '@/components/markdown/Markdown'
import { RESPONSIVE_DIALOG_OVERLAY } from '@/components/ui/responsiveDialog'
import { SIDE_PANEL_CONTENT, useSidePanelEntrance } from '@/components/ui/sidePanel'
import { cn } from '@/lib/utils'
import { getJiraIssueDetail, type JiraIssueDetail } from '@/jira/api'
import type { JiraConnection } from '@/jira/connection'

function statusBadgeClasses(category: string): string {
  if (category === 'done') return 'bg-success/15 text-success'
  if (category === 'indeterminate') return 'bg-accent-muted text-accent'
  return 'bg-surface-elevated text-text-secondary'
}

function formatDate(iso?: string): string | undefined {
  if (!iso) return undefined
  return new Date(iso).toLocaleString(undefined, { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' })
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1">
      <span className="text-xs font-medium text-text-secondary">{label}</span>
      <div className="text-sm text-text-primary">{children}</div>
    </div>
  )
}

function Person({ name, avatarUrl }: { name?: string; avatarUrl?: string }) {
  if (!name) return <span className="text-text-secondary">Unassigned</span>
  return (
    <span className="flex items-center gap-1.5">
      {avatarUrl && <img src={avatarUrl} alt="" className="h-4 w-4 shrink-0 rounded-full" />}
      {name}
    </span>
  )
}

/**
 * Read-only ticket detail — everything the search list can't show (full
 * description, reporter, labels, components, fix versions, dates,
 * resolution). Fetched separately from the search results (api/jira-issue.ts)
 * since Jira's search endpoint only ever returns the handful of fields
 * jira-search.ts asks for. Mirrors ItemDetailPanel's side-panel shape (see
 * components/ui/sidePanel.ts) for visual consistency with the rest of the
 * app, but has no edit affordances at all — this connection is read-only,
 * one-way, by design.
 */
export function JiraIssueDetailPanel({ connection, issueKey, onClose }: { connection: JiraConnection; issueKey: string; onClose: () => void }) {
  const [detail, setDetail] = useState<JiraIssueDetail | null>(null)
  const [error, setError] = useState<string | null>(null)
  const { contentClass, overlayClass } = useSidePanelEntrance()

  useEffect(() => {
    let cancelled = false
    setDetail(null)
    setError(null)
    getJiraIssueDetail(connection, issueKey)
      .then((result) => {
        if (!cancelled) setDetail(result)
      })
      .catch((err) => {
        if (!cancelled) setError(err instanceof Error ? err.message : String(err))
      })
    return () => {
      cancelled = true
    }
  }, [connection, issueKey])

  return (
    <Dialog.Root open onOpenChange={(open) => !open && onClose()}>
      <Dialog.Portal>
        <Dialog.Overlay className={cn(RESPONSIVE_DIALOG_OVERLAY, overlayClass)} />
        <Dialog.Content className={cn(SIDE_PANEL_CONTENT, contentClass)}>
          <div className="flex shrink-0 items-center justify-between border-b border-divider p-4">
            <div className="flex items-center gap-2">
              <Dialog.Title className="text-sm font-medium text-text-secondary">{issueKey}</Dialog.Title>
              {detail && (
                <a
                  href={detail.url}
                  target="_blank"
                  rel="noreferrer"
                  className="flex items-center gap-1 text-xs text-accent hover:underline"
                >
                  Open in Jira
                  <ExternalLink className="h-3 w-3" aria-hidden="true" />
                </a>
              )}
            </div>
            <Dialog.Close asChild>
              <button aria-label="Close" className="rounded-leo-sm p-1 text-text-secondary hover:bg-surface-elevated">
                <X className="h-4 w-4" />
              </button>
            </Dialog.Close>
          </div>

          <div className="min-h-0 flex-1 overflow-y-auto p-4">
            {error && <p className="text-sm text-danger">{error}</p>}

            {!detail && !error && <p className="text-sm text-text-secondary">Loading…</p>}

            {detail && (
              <div className="flex flex-col gap-4">
                <p className="text-lg font-semibold text-text-primary">{detail.summary}</p>

                <div className="flex flex-wrap items-center gap-1.5">
                  <span className={cn('rounded-leo-pill px-2 py-0.5 text-xs font-medium', statusBadgeClasses(detail.statusCategory))}>{detail.status}</span>
                  {detail.priorityName && (
                    <span className="flex items-center gap-1 rounded-leo-pill bg-surface-elevated px-2 py-0.5 text-xs font-medium text-text-secondary">
                      {detail.priorityIconUrl && <img src={detail.priorityIconUrl} alt="" className="h-3 w-3" />}
                      {detail.priorityName}
                    </span>
                  )}
                  <span className="flex items-center gap-1 rounded-leo-pill bg-surface-elevated px-2 py-0.5 text-xs font-medium text-text-secondary">
                    {detail.issueTypeIconUrl && <img src={detail.issueTypeIconUrl} alt="" className="h-3 w-3" />}
                    {detail.issueTypeName}
                  </span>
                  {detail.resolutionName && (
                    <span className="rounded-leo-pill bg-success/15 px-2 py-0.5 text-xs font-medium text-success">{detail.resolutionName}</span>
                  )}
                </div>

                <div className="grid grid-cols-2 gap-3">
                  <Field label="Assignee">
                    <Person name={detail.assigneeName} avatarUrl={detail.assigneeAvatarUrl} />
                  </Field>
                  <Field label="Reporter">
                    <Person name={detail.reporterName} avatarUrl={detail.reporterAvatarUrl} />
                  </Field>
                  {detail.projectName && <Field label="Project">{detail.projectName}</Field>}
                  {detail.dueDate && <Field label="Due">{formatDate(detail.dueDate)}</Field>}
                </div>

                {detail.labels.length > 0 && (
                  <Field label="Labels">
                    <div className="flex flex-wrap gap-1">
                      {detail.labels.map((label) => (
                        <span key={label} className="rounded-leo-pill bg-surface-elevated px-2 py-0.5 text-xs">
                          {label}
                        </span>
                      ))}
                    </div>
                  </Field>
                )}

                {detail.components.length > 0 && <Field label="Components">{detail.components.join(', ')}</Field>}
                {detail.fixVersions.length > 0 && <Field label="Fix versions">{detail.fixVersions.join(', ')}</Field>}

                {detail.descriptionMarkdown && (
                  <Field label="Description">
                    <Markdown text={detail.descriptionMarkdown} />
                  </Field>
                )}

                <p className="text-xs text-text-secondary">
                  {formatDate(detail.created) && `Created ${formatDate(detail.created)}`}
                  {formatDate(detail.updated) && ` · Updated ${formatDate(detail.updated)}`}
                </p>
              </div>
            )}
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  )
}
