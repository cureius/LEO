import { useMemo } from 'react'
import { useShallow } from 'zustand/react/shallow'
import { selectItemsArray, useSyncStore } from '@/sync/store'
import { anchorSortDate } from '@/wire/anchor'
import type { DomainItem, Tag } from '@/domain/types'

function byOpenThenCreatedAt(a: DomainItem, b: DomainItem): number {
  const aOpen = a.completion.type === 'open'
  const bOpen = b.completion.type === 'open'
  if (aOpen !== bOpen) return aOpen ? -1 : 1
  return a.createdAt.getTime() - b.createdAt.getTime()
}

/**
 * One project's items, partitioned into Timeline (anything with a date,
 * chronological) and Backlog (tasks with no date yet) — a strict partition,
 * not two overlapping views, so nothing shows up twice. Extracted from
 * ProjectDetailPage.tsx so PdfViewerPage's task sidebar can show the same
 * "everything filed under this project" view without duplicating the
 * filter/partition logic. A project is still just a tag name (see
 * domain/projects.ts) — this only reads that, matching items by tag NAME.
 */
export function useProjectItems(projectName: string) {
  const items = useSyncStore(useShallow(selectItemsArray))
  const initialLoadComplete = useSyncStore((s) => s.initialLoadComplete)

  const projectItems = useMemo(() => items.filter((i) => 'tags' in i && i.tags.some((t) => t.name === projectName)), [items, projectName])

  // The tag object itself (id/color) only exists embedded on items, never on
  // its own — grabbed from whichever item happens to carry it so callers
  // have a real Tag to pass to QuickAddForm's defaultTag.
  const tag: Tag | undefined = useMemo(() => {
    for (const item of projectItems) {
      if (!('tags' in item)) continue
      const found = item.tags.find((t) => t.name === projectName)
      if (found) return found
    }
    return undefined
  }, [projectItems, projectName])

  const taskCount = useMemo(() => projectItems.filter((i) => i.kind === 'task').length, [projectItems])
  const eventCount = useMemo(() => projectItems.filter((i) => i.kind === 'event').length, [projectItems])

  const timeline = useMemo(
    () =>
      projectItems
        .map((item) => ({ item, date: anchorSortDate(item.anchor) }))
        .filter((x): x is { item: DomainItem; date: Date } => x.date !== undefined)
        .sort((a, b) => a.date.getTime() - b.date.getTime())
        .map((x) => x.item),
    [projectItems],
  )

  const backlog = useMemo(
    () => projectItems.filter((i) => i.kind === 'task' && anchorSortDate(i.anchor) === undefined).sort(byOpenThenCreatedAt),
    [projectItems],
  )

  return { items: projectItems, tag, taskCount, eventCount, timeline, backlog, initialLoadComplete }
}
