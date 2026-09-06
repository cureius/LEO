import { ItemRow } from '@/components/items/ItemRow'
import { QuickAddForm } from '@/components/items/QuickAddForm'
import { useProjectItems } from '@/domain/useProjectItems'

/** The project's tasks/events, alongside the PDF reader — lets a task or
 *  event come out of a highlight without leaving the viewer. Same
 *  Timeline/Backlog partition as ProjectDetailPage.tsx (via
 *  useProjectItems), just laid out for a narrow sidebar column. */
export function ProjectTasksPanel({ projectName }: { projectName: string }) {
  const { tag, timeline, backlog, initialLoadComplete } = useProjectItems(projectName)

  return (
    <div className="flex h-full flex-col gap-4 overflow-y-auto p-4">
      {tag && <QuickAddForm defaultUntimed defaultTag={tag} allowEventKind />}

      {!initialLoadComplete && <p className="text-sm text-text-secondary">Loading…</p>}

      {initialLoadComplete && timeline.length === 0 && backlog.length === 0 && (
        <p className="text-sm text-text-secondary">Nothing filed under "{projectName}" yet.</p>
      )}

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
  )
}
