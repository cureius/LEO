import { useMemo, useState, type DragEvent } from 'react'
import { Link } from 'react-router-dom'
import { useShallow } from 'zustand/react/shallow'
import * as Dialog from '@radix-ui/react-dialog'
import { Pencil, Plus, Wand2, Trash2, X } from 'lucide-react'
import { ItemRow } from '@/components/items/ItemRow'
import { TagChip } from '@/components/ui/TagChip'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { ColorSwatchPicker } from '@/components/ui/ColorSwatchPicker'
import { RulesDialog } from '@/components/automation/RulesDialog'
import { RESPONSIVE_DIALOG_CONTENT, RESPONSIVE_DIALOG_OVERLAY } from '@/components/ui/responsiveDialog'
import { cn } from '@/lib/utils'
import { selectItemsArray, selectRulesArray, useSyncStore } from '@/sync/store'
import { createProject, deleteProject, reassignItemToProject, recolorProject, renameProject, unassignItem } from '@/domain/projects'
import { TAG_COLORS } from '@/domain/tagColors'
import type { DomainItem, Tag, TagColor } from '@/domain/types'

type ProjectGroup = { tag: Tag; items: DomainItem[] }

function NewProjectDialog({ onClose }: { onClose: () => void }) {
  const [name, setName] = useState('')
  const [color, setColor] = useState<TagColor>(TAG_COLORS[0])
  const [firstTask, setFirstTask] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleCreate() {
    if (!name.trim()) return
    setSaving(true)
    await createProject(name, color, firstTask)
    setSaving(false)
    onClose()
  }

  return (
    <Dialog.Root open onOpenChange={(open) => !open && onClose()}>
      <Dialog.Portal>
        <Dialog.Overlay className={RESPONSIVE_DIALOG_OVERLAY} />
        <Dialog.Content className={cn(RESPONSIVE_DIALOG_CONTENT, 'sm:max-w-sm bg-surface p-4 shadow-xl')}>
          <div className="mb-3 flex items-center justify-between">
            <Dialog.Title className="text-sm font-medium text-text-primary">New project</Dialog.Title>
            <Dialog.Close asChild>
              <button aria-label="Close" className="rounded-leo-sm p-1 text-text-secondary hover:bg-surface-elevated">
                <X className="h-4 w-4" />
              </button>
            </Dialog.Close>
          </div>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="project-name">Name</Label>
              <Input id="project-name" value={name} onChange={(e) => setName(e.target.value)} placeholder="Website redesign" autoFocus />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label>Color</Label>
              <ColorSwatchPicker value={color} onChange={setColor} />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="project-first-task">First task (optional)</Label>
              <Input id="project-first-task" value={firstTask} onChange={(e) => setFirstTask(e.target.value)} placeholder={name || 'What needs doing?'} />
              <p className="text-xs text-text-secondary">
                A project needs at least one task to exist — this creates the first one, untimed, in your backlog.
              </p>
            </div>
            <Button type="button" onClick={() => void handleCreate()} disabled={!name.trim() || saving} className="mt-1">
              {saving ? 'Creating…' : 'Create project'}
            </Button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  )
}

function EditProjectDialog({ group, items, onClose }: { group: ProjectGroup; items: DomainItem[]; onClose: () => void }) {
  const [name, setName] = useState(group.tag.name)
  const [color, setColor] = useState<TagColor>(group.tag.colorRaw)
  const [saving, setSaving] = useState(false)

  async function handleSave() {
    setSaving(true)
    if (name.trim() !== group.tag.name) await renameProject(items, group.tag.name, name)
    if (color !== group.tag.colorRaw) await recolorProject(items, name.trim() || group.tag.name, color)
    setSaving(false)
    onClose()
  }

  async function handleDelete() {
    setSaving(true)
    await deleteProject(items, group.tag.name)
    setSaving(false)
    onClose()
  }

  return (
    <Dialog.Root open onOpenChange={(open) => !open && onClose()}>
      <Dialog.Portal>
        <Dialog.Overlay className={RESPONSIVE_DIALOG_OVERLAY} />
        <Dialog.Content className={cn(RESPONSIVE_DIALOG_CONTENT, 'sm:max-w-sm bg-surface p-4 shadow-xl')}>
          <div className="mb-3 flex items-center justify-between">
            <Dialog.Title className="text-sm font-medium text-text-primary">Edit project</Dialog.Title>
            <Dialog.Close asChild>
              <button aria-label="Close" className="rounded-leo-sm p-1 text-text-secondary hover:bg-surface-elevated">
                <X className="h-4 w-4" />
              </button>
            </Dialog.Close>
          </div>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="project-edit-name">Name</Label>
              <Input id="project-edit-name" value={name} onChange={(e) => setName(e.target.value)} autoFocus />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label>Color</Label>
              <ColorSwatchPicker value={color} onChange={setColor} />
            </div>
            <div className="mt-1 flex items-center justify-between">
              <Button type="button" variant="ghost" onClick={() => void handleDelete()} disabled={saving} className="gap-1.5 text-danger hover:text-danger">
                <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
                Delete project
              </Button>
              <Button type="button" onClick={() => void handleSave()} disabled={!name.trim() || saving}>
                {saving ? 'Saving…' : 'Save'}
              </Button>
            </div>
            <p className="text-xs text-text-secondary">
              "Delete project" un-tags every item below — the tasks themselves aren't deleted, just no longer grouped here.
            </p>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  )
}

/**
 * Groups every taggable item (see domain/types.ts — everything except
 * HabitInstanceItem) by tag, alphabetically by tag name, plus real
 * create/rename/recolor/delete management (domain/projects.ts) — a
 * "project" IS a tag; see that file's doc comment for why every management
 * action here has to fan out across every item carrying it rather than
 * touching one row.
 */
const UNASSIGNED_KEY = '__unassigned__'

function byOpenThenTitle(a: DomainItem, b: DomainItem): number {
  const aOpen = a.completion.type === 'open'
  const bOpen = b.completion.type === 'open'
  if (aOpen !== bOpen) return aOpen ? -1 : 1
  return a.title.localeCompare(b.title)
}

export function ProjectsPage() {
  const items = useSyncStore(useShallow(selectItemsArray))
  const rules = useSyncStore(useShallow(selectRulesArray))
  const initialLoadComplete = useSyncStore((s) => s.initialLoadComplete)
  const [creating, setCreating] = useState(false)
  const [editingGroup, setEditingGroup] = useState<ProjectGroup | null>(null)
  const [managingRules, setManagingRules] = useState(false)
  const [draggedItemId, setDraggedItemId] = useState<string | null>(null)
  const [dragOverKey, setDragOverKey] = useState<string | null>(null)

  const groups = useMemo(() => {
    const byName = new Map<string, ProjectGroup>()
    for (const item of items) {
      const tags = 'tags' in item ? item.tags : []
      for (const tag of tags) {
        let group = byName.get(tag.name)
        if (!group) {
          group = { tag, items: [] }
          byName.set(tag.name, group)
        }
        group.items.push(item)
      }
    }
    for (const group of byName.values()) group.items.sort(byOpenThenTitle)
    return Array.from(byName.values()).sort((a, b) => a.tag.name.localeCompare(b.tag.name))
  }, [items])

  // Untagged-but-taggable items — nothing to drag FROM otherwise, since
  // every other view of this page only ever showed already-tagged items.
  const unassigned = useMemo(
    () => items.filter((i) => 'tags' in i && i.tags.length === 0).sort(byOpenThenTitle),
    [items],
  )

  function handleItemDragStart(e: DragEvent<HTMLLIElement>, item: DomainItem) {
    e.dataTransfer.setData('text/plain', item.id)
    e.dataTransfer.effectAllowed = 'move'
    setDraggedItemId(item.id)
  }

  function handleItemDragEnd() {
    setDraggedItemId(null)
    setDragOverKey(null)
  }

  function handleZoneDragOver(e: DragEvent<HTMLElement>, key: string) {
    e.preventDefault()
    e.dataTransfer.dropEffect = 'move'
    if (dragOverKey !== key) setDragOverKey(key)
  }

  function handleZoneDrop(e: DragEvent<HTMLElement>, target: { key: string; tag: Tag | null }) {
    e.preventDefault()
    const id = e.dataTransfer.getData('text/plain')
    const item = items.find((i) => i.id === id)
    setDraggedItemId(null)
    setDragOverKey(null)
    if (!item) return
    if (target.tag) void reassignItemToProject(item, target.tag)
    else void unassignItem(item)
  }

  return (
    <div className="flex h-full flex-col p-6">
      <div className="mb-1 flex shrink-0 items-center justify-between">
        <h1 className="text-xl font-semibold text-text-primary">Projects</h1>
        <div className="flex gap-1.5">
          <Button size="sm" variant="outline" onClick={() => setManagingRules(true)} className="gap-1.5">
            <Wand2 className="h-3.5 w-3.5" aria-hidden="true" />
            Rules
          </Button>
          <Button size="sm" onClick={() => setCreating(true)} className="gap-1.5">
            <Plus className="h-3.5 w-3.5" aria-hidden="true" />
            New Project
          </Button>
        </div>
      </div>
      <p className="mb-4 shrink-0 text-sm text-text-secondary">
        Everything tagged, grouped by project. Drag a task onto a project to assign it — onto Unassigned to remove it from
        one, or set up a Rule to file matching items in automatically.
      </p>

      {!initialLoadComplete && <p className="text-sm text-text-secondary">Loading…</p>}

      {initialLoadComplete && groups.length === 0 && unassigned.length === 0 && (
        <p className="text-sm text-text-secondary">No projects yet — click "New Project" to start one.</p>
      )}

      {/* Kanban-style columns, not a stack — each project (plus Unassigned)
          is a fixed-width column so the board reads as a board on a wide
          screen instead of a single narrow list with empty space on either
          side. flex-1 + min-h-0 lets the row (and each column's own list)
          fill the rest of the viewport instead of stopping at its content
          height with a dead gap below. The drag-and-drop logic itself
          didn't need to change at all: each <section> is still the same
          drop zone, just laid out horizontally now instead of vertically. */}
      <div className="flex min-h-0 flex-1 items-stretch gap-4 overflow-x-auto pb-2">
        {(groups.length > 0 || unassigned.length > 0) && (
          <section
            onDragOver={(e) => handleZoneDragOver(e, UNASSIGNED_KEY)}
            onDrop={(e) => handleZoneDrop(e, { key: UNASSIGNED_KEY, tag: null })}
            className={cn(
              'flex w-72 shrink-0 flex-col rounded-leo-md border-2 p-2 transition-colors',
              dragOverKey === UNASSIGNED_KEY ? 'border-accent bg-accent-muted/40' : 'border-divider',
            )}
          >
            <div className="mb-2 flex shrink-0 items-center gap-2">
              <span className="text-xs font-medium tracking-wide text-text-secondary uppercase">Unassigned</span>
              <span className="text-xs text-text-secondary">{unassigned.length}</span>
            </div>
            {unassigned.length === 0 ? (
              <p className="text-xs text-text-secondary">Drag a task here to remove it from a project.</p>
            ) : (
              <ul className="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto">
                {unassigned.map((item) => (
                  <ItemRow
                    key={`unassigned-${item.id}`}
                    item={item}
                    draggable
                    onDragStart={(e) => handleItemDragStart(e, item)}
                    onDragEnd={handleItemDragEnd}
                    className={item.id === draggedItemId ? 'opacity-40' : undefined}
                    showTags={false}
                  />
                ))}
              </ul>
            )}
          </section>
        )}

        {groups.map((group) => (
          <section
            key={group.tag.name}
            onDragOver={(e) => handleZoneDragOver(e, group.tag.name)}
            onDrop={(e) => handleZoneDrop(e, { key: group.tag.name, tag: group.tag })}
            className={cn(
              'flex w-72 shrink-0 flex-col rounded-leo-md border-2 p-2 transition-colors',
              dragOverKey === group.tag.name ? 'border-accent bg-accent-muted/40' : 'border-divider',
            )}
          >
            <div className="mb-2 flex shrink-0 items-center gap-2">
              <Link to={`/projects/${encodeURIComponent(group.tag.name)}`} className="rounded-leo-sm hover:opacity-80" aria-label={`Open project "${group.tag.name}"`}>
                <TagChip tag={group.tag} />
              </Link>
              <span className="text-xs text-text-secondary">{group.items.length}</span>
              <button
                type="button"
                onClick={() => setEditingGroup(group)}
                aria-label={`Edit project "${group.tag.name}"`}
                className="rounded-leo-sm p-1 text-text-secondary hover:bg-surface-elevated hover:text-text-primary"
              >
                <Pencil className="h-3.5 w-3.5" />
              </button>
            </div>
            <ul className="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto">
              {group.items.map((item) => (
                <ItemRow
                  key={`${group.tag.name}-${item.id}`}
                  item={item}
                  draggable
                  onDragStart={(e) => handleItemDragStart(e, item)}
                  onDragEnd={handleItemDragEnd}
                  className={item.id === draggedItemId ? 'opacity-40' : undefined}
                  showTags={false}
                />
              ))}
            </ul>
          </section>
        ))}
      </div>

      {creating && <NewProjectDialog onClose={() => setCreating(false)} />}
      {editingGroup && <EditProjectDialog group={editingGroup} items={items} onClose={() => setEditingGroup(null)} />}
      {managingRules && <RulesDialog items={items} rules={rules} onClose={() => setManagingRules(false)} />}
    </div>
  )
}
