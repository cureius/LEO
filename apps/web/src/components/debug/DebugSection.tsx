import { useState } from 'react'
import { toast } from 'sonner'
import { ChevronLeft, ChevronRight, Pencil, Plus, Trash2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import { JsonEditorModal } from './JsonEditorModal'
import { errorMessage } from '@/sync/mutations'

export type DebugRecord = { id: string; label: string; sublabel?: string; raw: unknown }

const PAGE_SIZE = 20

/**
 * One table of records with select/bulk-select and per-row edit/delete —
 * reused for Items, Habits, and Measurements on DebugPage rather than
 * building three bespoke tables. Every write funnels through the same
 * mutation functions the rest of the app uses (passed in by the caller),
 * so this is a real admin surface over live data, not a separate mock path.
 *
 * Select-all and bulk-delete operate over the FULL record set, not just the
 * current page — paging only changes what's rendered, not what a prior
 * "select all" already selected, so you can still bulk-delete hundreds of
 * rows without paging through them all first.
 */
export function DebugSection({
  title,
  records,
  newTemplate,
  onSave,
  onDelete,
}: {
  title: string
  records: DebugRecord[]
  /** Starter JSON shown when creating a new record — caller-provided since
   *  the shape differs entirely between an Item, a Habit, and a Measurement. */
  newTemplate: () => unknown
  onSave: (id: string | null, parsed: Record<string, unknown>) => Promise<void>
  onDelete: (record: DebugRecord) => Promise<void>
}) {
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [editing, setEditing] = useState<{ id: string | null; raw: unknown } | null>(null)
  const [deleting, setDeleting] = useState(false)
  const [page, setPage] = useState(0)

  const pageCount = Math.max(Math.ceil(records.length / PAGE_SIZE), 1)
  // Clamped rather than stored directly — e.g. bulk-deleting everything on
  // the last page must not leave `page` pointing past the new, shorter list.
  const currentPage = Math.min(page, pageCount - 1)
  const pageRecords = records.slice(currentPage * PAGE_SIZE, currentPage * PAGE_SIZE + PAGE_SIZE)

  const allSelected = records.length > 0 && records.every((r) => selectedIds.has(r.id))

  function toggleSelect(id: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  function toggleSelectAll() {
    setSelectedIds(allSelected ? new Set() : new Set(records.map((r) => r.id)))
  }

  /** allSettled, not all — a single failure (e.g. an EventKit-synced item,
   *  structurally read-only in deleteItem) must not abort every OTHER
   *  deletion in the batch, and must never surface as an unhandled promise
   *  rejection with no user-facing feedback at all — confirmed live: that's
   *  exactly what Promise.all + no .catch produced here before. */
  async function handleBulkDelete() {
    setDeleting(true)
    const toDelete = records.filter((r) => selectedIds.has(r.id))
    const results = await Promise.allSettled(toDelete.map((r) => onDelete(r)))

    const failed = results
      .map((result, i) => ({ result, record: toDelete[i] }))
      .filter((x): x is { result: PromiseRejectedResult; record: DebugRecord } => x.result.status === 'rejected')

    if (failed.length > 0) {
      toast.error(`Couldn't delete ${failed.length} of ${toDelete.length}`, {
        description: failed.map((f) => `${f.record.label}: ${errorMessage(f.result.reason)}`).join('\n'),
      })
    }

    // Successfully-deleted rows drop out of the selection; failed ones stay
    // selected so it's obvious which rows the bulk action didn't clear.
    const failedIds = new Set(failed.map((f) => f.record.id))
    setSelectedIds((prev) => new Set([...prev].filter((id) => failedIds.has(id))))
    setDeleting(false)
  }

  async function handleSingleDelete(record: DebugRecord) {
    try {
      await onDelete(record)
    } catch (err) {
      toast.error(`Couldn't delete "${record.label}"`, { description: errorMessage(err) })
    }
  }

  return (
    <section className="mb-6 rounded-leo-md border border-divider bg-surface p-4">
      <div className="mb-3 flex items-center justify-between">
        <h2 className="text-sm font-semibold text-text-primary">
          {title} — {records.length}
        </h2>
        <div className="flex items-center gap-1.5">
          {selectedIds.size > 0 && (
            <Button variant="destructive" size="sm" onClick={() => void handleBulkDelete()} disabled={deleting} className="gap-1.5">
              <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
              {deleting ? 'Deleting…' : `Delete (${selectedIds.size})`}
            </Button>
          )}
          <Button variant="ghost" size="sm" onClick={() => setEditing({ id: null, raw: newTemplate() })} className="gap-1.5 text-text-secondary">
            <Plus className="h-3.5 w-3.5" aria-hidden="true" />
            New
          </Button>
        </div>
      </div>

      {records.length === 0 ? (
        <p className="text-xs text-text-secondary">No entries.</p>
      ) : (
        <>
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-sm">
              <thead>
                <tr className="border-b border-divider text-left text-xs text-text-secondary">
                  <th className="w-8 py-1.5 pr-2">
                    <Checkbox checked={allSelected} onCheckedChange={toggleSelectAll} aria-label={`Select all ${title}`} />
                  </th>
                  <th className="py-1.5 pr-3 font-medium">Label</th>
                  <th className="py-1.5 pr-3 font-medium">ID</th>
                  <th className="w-16 py-1.5" />
                </tr>
              </thead>
              <tbody>
                {pageRecords.map((r) => (
                  <tr key={r.id} className="border-b border-divider last:border-0 hover:bg-surface-elevated">
                    <td className="py-1.5 pr-2">
                      <Checkbox checked={selectedIds.has(r.id)} onCheckedChange={() => toggleSelect(r.id)} aria-label={`Select ${r.label}`} />
                    </td>
                    <td className="max-w-xs truncate py-1.5 pr-3 text-text-primary">{r.label}</td>
                    <td className="max-w-[160px] truncate py-1.5 pr-3 font-mono text-[11px] text-text-secondary">{r.sublabel}</td>
                    <td className="py-1.5">
                      <div className="flex justify-end gap-1">
                        <Button variant="ghost" size="icon-sm" aria-label={`Edit ${r.label}`} onClick={() => setEditing({ id: r.id, raw: r.raw })}>
                          <Pencil className="h-3.5 w-3.5" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon-sm"
                          aria-label={`Delete ${r.label}`}
                          className="text-text-secondary hover:text-danger"
                          onClick={() => void handleSingleDelete(r)}
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </Button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {pageCount > 1 && (
            <div className="mt-2 flex items-center justify-between text-xs text-text-secondary">
              <span>
                Page {currentPage + 1} of {pageCount}
              </span>
              <div className="flex gap-1">
                <Button variant="outline" size="icon-sm" disabled={currentPage === 0} onClick={() => setPage(currentPage - 1)} aria-label="Previous page">
                  <ChevronLeft className="h-3.5 w-3.5" />
                </Button>
                <Button
                  variant="outline"
                  size="icon-sm"
                  disabled={currentPage >= pageCount - 1}
                  onClick={() => setPage(currentPage + 1)}
                  aria-label="Next page"
                >
                  <ChevronRight className="h-3.5 w-3.5" />
                </Button>
              </div>
            </div>
          )}
        </>
      )}

      {editing && (
        <JsonEditorModal
          title={editing.id ? `Edit ${title.replace(/s$/, '')}` : `New ${title.replace(/s$/, '')}`}
          initialValue={editing.raw}
          onSave={(parsed) => onSave(editing.id, parsed)}
          onClose={() => setEditing(null)}
        />
      )}
    </section>
  )
}
