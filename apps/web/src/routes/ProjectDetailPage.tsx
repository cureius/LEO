import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, FileText } from 'lucide-react'
import { ItemRow } from '@/components/items/ItemRow'
import { QuickAddForm } from '@/components/items/QuickAddForm'
import { MarkdownField } from '@/components/markdown/MarkdownField'
import { Button } from '@/components/ui/button'
import { TagChip } from '@/components/ui/TagChip'
import { useProjectItems } from '@/domain/useProjectItems'
import { getProjectNotes, saveProjectNotes } from '@/domain/projectNotes'

/**
 * One project's full picture — a project-level markdown doc, then every
 * task/event split into Timeline (anything with a date, chronological) and
 * Backlog (tasks with no date yet) — a strict partition, not two
 * overlapping views, so nothing shows up twice. Reached by clicking a
 * project on ProjectsPage.tsx (the kanban board there stays the fast
 * drag-and-drop triage view; this is the "zoom in on one project" view).
 * A project is still just a tag name (see domain/projects.ts) — this page
 * only adds a place to READ that, plus the one genuinely new piece of state,
 * the project-level notes doc (domain/projectNotes.ts), which has nowhere
 * else to live since there's no project registry row.
 */
export function ProjectDetailPage() {
  const { name } = useParams<{ name: string }>()
  const projectName = decodeURIComponent(name ?? '')
  const { items: projectItems, tag, taskCount, eventCount, timeline, backlog, initialLoadComplete } = useProjectItems(projectName)

  const [notes, setNotes] = useState('')
  const [notesLoaded, setNotesLoaded] = useState(false)
  const [notesDirty, setNotesDirty] = useState(false)
  const [savingNotes, setSavingNotes] = useState(false)

  useEffect(() => {
    let cancelled = false
    setNotesLoaded(false)
    getProjectNotes(projectName)
      .catch(() => '') // a failed load still needs to unblock the field — falls back to an empty (editable, re-saveable) doc rather than a permanently stuck "Loading notes…"
      .then((loaded) => {
        if (cancelled) return
        setNotes(loaded)
        setNotesDirty(false)
        setNotesLoaded(true)
      })
    return () => {
      cancelled = true
    }
  }, [projectName])

  async function handleSaveNotes() {
    setSavingNotes(true)
    try {
      await saveProjectNotes(projectName, notes)
      setNotesDirty(false)
    } finally {
      setSavingNotes(false)
    }
  }

  return (
    <div className="p-6">
      <Link to="/projects" className="mb-3 inline-flex w-fit items-center gap-1.5 text-sm text-text-secondary hover:text-text-primary">
        <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
        Projects
      </Link>

      <div className="mb-1 flex items-center justify-between gap-2">
        {tag ? <TagChip tag={tag} /> : <h1 className="text-xl font-semibold text-text-primary">{projectName}</h1>}
        <Button asChild type="button" size="sm" variant="outline">
          <Link to={`/projects/${encodeURIComponent(projectName)}/pdfs`}>
            <FileText className="h-3.5 w-3.5" aria-hidden="true" />
            PDFs
          </Link>
        </Button>
      </div>
      <p className="mb-4 text-sm text-text-secondary">
        {taskCount} task{taskCount === 1 ? '' : 's'} · {eventCount} event{eventCount === 1 ? '' : 's'}
      </p>

      {!initialLoadComplete && <p className="text-sm text-text-secondary">Loading…</p>}

      {initialLoadComplete && projectItems.length === 0 && <p className="text-sm text-text-secondary">Nothing filed under "{projectName}" yet.</p>}

      {initialLoadComplete && (
        <div className="flex flex-col gap-6">
          <section className="rounded-leo-md border border-divider bg-surface p-4">
            {notesLoaded ? (
              <>
                <MarkdownField
                  id="project-notes"
                  label="Notes"
                  value={notes}
                  onChange={(next) => {
                    setNotes(next)
                    setNotesDirty(true)
                  }}
                  rows={6}
                  placeholder="What's this project about?"
                />
                <div className="mt-2 flex justify-end">
                  <Button size="sm" onClick={() => void handleSaveNotes()} disabled={!notesDirty || savingNotes}>
                    {savingNotes ? 'Saving…' : 'Save notes'}
                  </Button>
                </div>
              </>
            ) : (
              <p className="text-sm text-text-secondary">Loading notes…</p>
            )}
          </section>

          {tag && <QuickAddForm defaultUntimed defaultTag={tag} allowEventKind />}

          {timeline.length > 0 && (
            <section>
              <h2 className="mb-2 text-xs font-medium uppercase tracking-wide text-text-secondary">Timeline — {timeline.length}</h2>
              <ul className="flex flex-col gap-2">
                {timeline.map((item) => (
                  <ItemRow key={item.id} item={item} showTags={false} />
                ))}
              </ul>
            </section>
          )}

          {backlog.length > 0 && (
            <section>
              <h2 className="mb-2 text-xs font-medium uppercase tracking-wide text-text-secondary">Backlog — {backlog.length}</h2>
              <ul className="flex flex-col gap-2">
                {backlog.map((item) => (
                  <ItemRow key={item.id} item={item} showTags={false} />
                ))}
              </ul>
            </section>
          )}
        </div>
      )}
    </div>
  )
}
