import { addItem, updateItem } from '@/sync/mutations'
import type { DomainItem, Tag, TaskItem } from '@/domain/types'

/**
 * A "project" IS a tag — see TagEditor.tsx's doc comment: tags are embedded
 * per-item (no standalone registry table), matched across items by NAME not
 * id. That means a project can't exist with zero items (there's nowhere to
 * persist it), and renaming/recoloring/deleting one means touching every
 * item that currently carries a tag with that name — there's no single row
 * to update. These helpers do that fan-out; ProjectsPage.tsx just calls them.
 */

/** A project can't be created with no items at all (nothing to attach the
 *  tag to) — this creates one untimed starter task carrying the new tag,
 *  which is what makes the project actually show up anywhere. */
export async function createProject(name: string, color: Tag['colorRaw'], firstTaskTitle: string): Promise<void> {
  const now = new Date()
  const task: TaskItem = {
    kind: 'task',
    id: crypto.randomUUID(),
    title: firstTaskTitle.trim() || name.trim(),
    createdAt: now,
    updatedAt: now,
    importance: 1,
    anchor: { type: 'untimed' },
    completion: { type: 'open' },
    tags: [{ id: crypto.randomUUID(), name: name.trim(), colorRaw: color }],
  }
  await addItem(task)
}

function itemsWithProjectTag(items: DomainItem[], name: string): DomainItem[] {
  return items.filter((item) => 'tags' in item && item.tags.some((t) => t.name === name))
}

export async function renameProject(items: DomainItem[], oldName: string, newName: string): Promise<void> {
  const trimmed = newName.trim()
  if (!trimmed || trimmed === oldName) return
  const affected = itemsWithProjectTag(items, oldName)
  await Promise.allSettled(
    affected.map((item) => {
      if (!('tags' in item)) return Promise.resolve()
      const tags = item.tags.map((t) => (t.name === oldName ? { ...t, name: trimmed } : t))
      return updateItem({ ...item, tags })
    }),
  )
}

export async function recolorProject(items: DomainItem[], name: string, color: Tag['colorRaw']): Promise<void> {
  const affected = itemsWithProjectTag(items, name)
  await Promise.allSettled(
    affected.map((item) => {
      if (!('tags' in item)) return Promise.resolve()
      const tags = item.tags.map((t) => (t.name === name ? { ...t, colorRaw: color } : t))
      return updateItem({ ...item, tags })
    }),
  )
}

/** Drag-and-drop reassign: REPLACES an item's project tags with just the
 *  target project's — dropping a task onto a different project reads as
 *  "move it there," not "also file it there." Multi-project membership is
 *  still reachable via the task detail's own tag editor for anyone who
 *  wants it deliberately; drag-drop just isn't the interaction for that. */
export async function reassignItemToProject(item: DomainItem, tag: Tag): Promise<void> {
  if (!('tags' in item)) return
  const alreadyOnlyThis = item.tags.length === 1 && item.tags[0].name === tag.name
  if (alreadyOnlyThis) return
  await updateItem({ ...item, tags: [tag] })
}

/** Dropping onto the Unassigned zone — clears every project tag. */
export async function unassignItem(item: DomainItem): Promise<void> {
  if (!('tags' in item) || item.tags.length === 0) return
  await updateItem({ ...item, tags: [] })
}

/** Removes the tag from every item that has it — the items themselves
 *  survive (they just stop being part of this project), matching how
 *  deleting a project reads to a user ("un-file these," not "destroy
 *  everything filed under it"). Deleting the actual tasks is a separate,
 *  ordinary bulk-delete action already available elsewhere (Today/Inbox
 *  select mode, Debug page). */
export async function deleteProject(items: DomainItem[], name: string): Promise<void> {
  const affected = itemsWithProjectTag(items, name)
  await Promise.allSettled(
    affected.map((item) => {
      if (!('tags' in item)) return Promise.resolve()
      const tags = item.tags.filter((t) => t.name !== name)
      return updateItem({ ...item, tags })
    }),
  )
}
