import { useState, type DragEvent } from 'react'
import { useShallow } from 'zustand/react/shallow'
import { CalendarClock, CheckSquare, Moon, X } from 'lucide-react'
import { QuickAddForm } from '@/components/items/QuickAddForm'
import { ItemRow } from '@/components/items/ItemRow'
import { Button } from '@/components/ui/button'
import { DateTimePicker } from '@/components/ui/DateTimePicker'
import { cn } from '@/lib/utils'
import { selectItemsArray, useSyncStore } from '@/sync/store'
import { updateItem } from '@/sync/mutations'
import { endOfDay } from '@/domain/dates'
import { anchorIsUntimed } from '@/wire/anchor'
import { isExternallyManaged } from '@/wire/items'
import type { DomainItem } from '@/domain/types'

const IMPORTANCE_GROUPS: { level: number; label: string }[] = [
  { level: 3, label: 'Urgent' },
  { level: 2, label: 'High' },
  { level: 1, label: 'Normal' },
  { level: 0, label: 'Low' },
]

/**
 * Port of InboxView.swift: the untimed backlog grouped by importance, not a
 * flat list — this is a triage view. The same items also surface as
 * Today's "Backlog" section when viewing today (TodayPage.tsx); Inbox is
 * specifically for working through the whole backlog by priority.
 */
export function InboxPage() {
  const items = useSyncStore(useShallow(selectItemsArray))
  const initialLoadComplete = useSyncStore((s) => s.initialLoadComplete)

  const [selectMode, setSelectMode] = useState(false)
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [customDate, setCustomDate] = useState('')
  const [applying, setApplying] = useState(false)
  const [draggedItemId, setDraggedItemId] = useState<string | null>(null)
  const [dragOverLevel, setDragOverLevel] = useState<number | null>(null)

  const untimed = items.filter((i) => i.kind !== 'habitInstance' && anchorIsUntimed(i.anchor))
  const open = untimed.filter((i) => i.completion.type === 'open')
  const completed = untimed.filter((i) => i.completion.type !== 'open')

  // Every column always renders, even empty ones — a kanban board needs a
  // visible drop target for a priority level that currently has nothing in
  // it, not just the ones already populated.
  const groups = IMPORTANCE_GROUPS.map((g) => ({
    ...g,
    items: open.filter((i) => i.importance === g.level) as DomainItem[],
  }))

  function handleItemDragStart(e: DragEvent<HTMLLIElement>, item: DomainItem) {
    e.dataTransfer.setData('text/plain', item.id)
    e.dataTransfer.effectAllowed = 'move'
    setDraggedItemId(item.id)
  }

  function handleItemDragEnd() {
    setDraggedItemId(null)
    setDragOverLevel(null)
  }

  function handleColumnDragOver(e: DragEvent<HTMLElement>, level: number) {
    e.preventDefault()
    e.dataTransfer.dropEffect = 'move'
    if (dragOverLevel !== level) setDragOverLevel(level)
  }

  function handleColumnDrop(e: DragEvent<HTMLElement>, level: number) {
    e.preventDefault()
    const id = e.dataTransfer.getData('text/plain')
    setDraggedItemId(null)
    setDragOverLevel(null)
    const item = open.find((i) => i.id === id)
    if (!item || item.importance === level) return
    void updateItem({ ...item, importance: level })
  }

  // Selectable set is just the open backlog — assigning a due date to an
  // already-completed item isn't a meaningful action this bar offers.
  const selectableItems = open

  function toggleSelect(id: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  function exitSelectMode() {
    setSelectMode(false)
    setSelectedIds(new Set())
    setCustomDate('')
  }

  /** Assigning a date/time moves these off the untimed backlog entirely —
   *  that's the point (Inbox is specifically the UNTIMED list, see the
   *  module doc comment), not a bug where selected items "disappear." */
  async function applyDate(isoDate: string) {
    setApplying(true)
    try {
      const toUpdate = selectableItems.filter((i) => selectedIds.has(i.id))
      await Promise.allSettled(toUpdate.map((item) => updateItem({ ...item, anchor: { type: 'dueAt', date: isoDate } })))
      exitSelectMode()
    } finally {
      setApplying(false)
    }
  }

  return (
    <div className="p-6">
      <div className="mb-1 flex items-center justify-between">
        <h1 className="text-xl font-semibold text-text-primary">Inbox</h1>
        {selectableItems.length > 0 &&
          (selectMode ? (
            <div className="flex flex-wrap items-center justify-end gap-1.5">
              <span className="text-sm text-text-secondary">{selectedIds.size} selected</span>
              <Button
                variant="outline"
                size="sm"
                onClick={() => void applyDate(endOfDay(new Date()).toISOString())}
                disabled={selectedIds.size === 0 || applying}
                className="gap-1.5"
              >
                <Moon className="h-3.5 w-3.5" aria-hidden="true" />
                EOD
              </Button>
              <DateTimePicker value={customDate} onChange={setCustomDate} className="w-[200px]" placeholder="Custom date & time" />
              <Button
                variant="outline"
                size="sm"
                onClick={() => customDate && void applyDate(customDate)}
                disabled={selectedIds.size === 0 || !customDate || applying}
                className="gap-1.5"
              >
                <CalendarClock className="h-3.5 w-3.5" aria-hidden="true" />
                {applying ? 'Applying…' : 'Apply'}
              </Button>
              <Button variant="ghost" size="sm" onClick={exitSelectMode} className="gap-1.5 text-text-secondary">
                <X className="h-3.5 w-3.5" aria-hidden="true" />
                Cancel
              </Button>
            </div>
          ) : (
            <Button variant="ghost" size="sm" onClick={() => setSelectMode(true)} className="gap-1.5 text-text-secondary">
              <CheckSquare className="h-3.5 w-3.5" aria-hidden="true" />
              Select
            </Button>
          ))}
      </div>
      <p className="mb-4 text-sm text-text-secondary">Your untimed backlog, by priority. Drag a task between columns to change its priority.</p>

      <QuickAddForm defaultUntimed />

      {!initialLoadComplete && <p className="text-sm text-text-secondary">Loading…</p>}

      {initialLoadComplete && open.length === 0 && completed.length === 0 && (
        <p className="text-sm text-text-secondary">Inbox is empty.</p>
      )}

      {/* Kanban board — one column per priority level, always all four so
          an empty priority still offers a drop target. Same native-DnD
          pattern as ProjectsPage's project columns (see its doc comment):
          each <section> is the drop zone, dataTransfer carries the item id,
          and dropping calls updateItem with the target column's importance
          instead of reassigning a tag. */}
      {open.length > 0 && (
        <div className="mb-6 flex items-start gap-4 overflow-x-auto pb-2">
          {groups.map((group) => (
            <section
              key={group.level}
              onDragOver={(e) => handleColumnDragOver(e, group.level)}
              onDrop={(e) => handleColumnDrop(e, group.level)}
              className={cn(
                'w-72 shrink-0 rounded-leo-md border-2 p-2 transition-colors',
                dragOverLevel === group.level ? 'border-accent bg-accent-muted/40' : 'border-divider',
              )}
            >
              <h2 className="mb-2 flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-text-secondary">
                {group.label}
                <span className="text-text-secondary">{group.items.length}</span>
              </h2>
              {group.items.length === 0 ? (
                <p className="text-xs text-text-secondary">Drag a task here to set it to {group.label.toLowerCase()} priority.</p>
              ) : (
                <ul className="flex max-h-[70vh] flex-col gap-2 overflow-y-auto">
                  {group.items.map((item) => (
                    <ItemRow
                      key={item.id}
                      item={item}
                      selectMode={selectMode}
                      selected={selectedIds.has(item.id)}
                      onToggleSelect={() => toggleSelect(item.id)}
                      draggable={!selectMode && !isExternallyManaged(item)}
                      onDragStart={(e) => handleItemDragStart(e, item)}
                      onDragEnd={handleItemDragEnd}
                      className={item.id === draggedItemId ? 'opacity-40' : undefined}
                      showImportance={false}
                    />
                  ))}
                </ul>
              )}
            </section>
          ))}
        </div>
      )}

      {completed.length > 0 && (
        <section>
          <h2 className="mb-2 text-xs font-medium uppercase tracking-wide text-text-secondary">
            Completed — {completed.length}
          </h2>
          <ul className="flex flex-col gap-2">
            {completed.map((item) => (
              <ItemRow key={item.id} item={item} />
            ))}
          </ul>
        </section>
      )}
    </div>
  )
}
