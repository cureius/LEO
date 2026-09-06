import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useShallow } from 'zustand/react/shallow'
import * as Dialog from '@radix-ui/react-dialog'
import {
  Search,
  FolderKanban,
  Repeat,
  X,
  Bell,
  BellOff,
  Calendar,
  CalendarCheck,
  CheckCircle2,
  Circle,
  Dumbbell,
  UtensilsCrossed,
} from 'lucide-react'
import { ItemDetailPanel } from '@/components/items/ItemDetailPanel'
import { TagChip } from '@/components/ui/TagChip'
import { cn } from '@/lib/utils'
import { selectHabitsArray, selectItemsArray, useSyncStore } from '@/sync/store'
import { kindLabel, secondaryLineFor, completionIconFor, type CompletionIconKind } from '@/domain/itemDisplay'
import type { DomainItem, Habit, Tag } from '@/domain/types'

const ICONS: Record<CompletionIconKind, typeof Circle> = {
  bell: Bell,
  bellOff: BellOff,
  circleDot: Circle,
  circleFilled: CheckCircle2,
  calendar: Calendar,
  calendarCheck: CalendarCheck,
  dumbbell: Dumbbell,
  utensils: UtensilsCrossed,
  checkCircle: CheckCircle2,
  circle: Circle,
}

const MAX_RESULTS_PER_GROUP = 8

type ItemResult = { type: 'item'; item: DomainItem }
type ProjectResult = { type: 'project'; tag: Tag; count: number }
type HabitResult = { type: 'habit'; habit: Habit }
type Result = ItemResult | ProjectResult | HabitResult

function matches(haystack: string | undefined, query: string): boolean {
  return !!haystack && haystack.toLowerCase().includes(query)
}

/**
 * Cmd/Ctrl+F opens this from anywhere in the app (mounted once in
 * AppShell) — a single search box over every entity LEO knows about:
 * tasks, events, reminders, alarms, workouts, meals (all DomainItem kinds,
 * via selectItemsArray), habits (selectHabitsArray, a separate store slice
 * — see domain/types.ts's Habit vs. HabitInstanceItem split), and projects
 * (derived from item tags, same "a project IS a tag" model as
 * ProjectsPage). Picking an item result opens the same ItemDetailPanel
 * ItemRow uses; habits and projects don't have a standalone detail view,
 * so those just navigate to their list page.
 */
export function GlobalSearch() {
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [openItem, setOpenItem] = useState<DomainItem | undefined>(undefined)
  const inputRef = useRef<HTMLInputElement>(null)
  const navigate = useNavigate()

  const items = useSyncStore(useShallow(selectItemsArray))
  const habits = useSyncStore(useShallow(selectHabitsArray))

  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      const isFindShortcut = (e.metaKey || e.ctrlKey) && !e.shiftKey && !e.altKey && e.key.toLowerCase() === 'f'
      if (!isFindShortcut) return
      e.preventDefault()
      setOpen(true)
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [])

  useEffect(() => {
    if (open) {
      setQuery('')
      // Radix moves focus into the dialog on open; grab the input right after.
      requestAnimationFrame(() => inputRef.current?.focus())
    }
  }, [open])

  const projects = useMemo(() => {
    const byName = new Map<string, { tag: Tag; count: number }>()
    for (const item of items) {
      const tags = 'tags' in item ? item.tags : []
      for (const tag of tags) {
        const existing = byName.get(tag.name)
        if (existing) existing.count += 1
        else byName.set(tag.name, { tag, count: 1 })
      }
    }
    return Array.from(byName.values())
  }, [items])

  const results = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return { items: [] as ItemResult[], projects: [] as ProjectResult[], habits: [] as HabitResult[] }

    const itemResults: ItemResult[] = items
      .filter((item) => matches(item.title, q) || matches(item.notes, q))
      .slice(0, MAX_RESULTS_PER_GROUP)
      .map((item) => ({ type: 'item', item }))

    const projectResults: ProjectResult[] = projects
      .filter((p) => matches(p.tag.name, q))
      .slice(0, MAX_RESULTS_PER_GROUP)
      .map((p) => ({ type: 'project', tag: p.tag, count: p.count }))

    const habitResults: HabitResult[] = habits
      .filter((h) => matches(h.name, q))
      .slice(0, MAX_RESULTS_PER_GROUP)
      .map((h) => ({ type: 'habit', habit: h }))

    return { items: itemResults, projects: projectResults, habits: habitResults }
  }, [query, items, projects, habits])

  const flatResults: Result[] = [...results.items, ...results.projects, ...results.habits]
  const [activeIndex, setActiveIndex] = useState(0)

  useEffect(() => {
    setActiveIndex(0)
  }, [query])

  function selectResult(result: Result) {
    setOpen(false)
    if (result.type === 'item') setOpenItem(result.item)
    else if (result.type === 'project') navigate(`/projects/${encodeURIComponent(result.tag.name)}`)
    else navigate('/habits')
  }

  function handleInputKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setActiveIndex((i) => Math.min(i + 1, flatResults.length - 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setActiveIndex((i) => Math.max(i - 1, 0))
    } else if (e.key === 'Enter') {
      e.preventDefault()
      const result = flatResults[activeIndex]
      if (result) selectResult(result)
    }
  }

  return (
    <>
      <Dialog.Root open={open} onOpenChange={setOpen}>
        <Dialog.Portal>
          <Dialog.Overlay className="fixed inset-0 z-50 bg-black/40" />
          <Dialog.Content
            className="fixed top-[12vh] left-1/2 z-50 flex max-h-[70vh] w-[min(560px,calc(100vw-2rem))] -translate-x-1/2 flex-col overflow-hidden rounded-leo-md border border-divider bg-surface shadow-xl"
            onOpenAutoFocus={(e) => {
              e.preventDefault()
              inputRef.current?.focus()
            }}
          >
            <Dialog.Title className="sr-only">Search</Dialog.Title>
            <div className="flex shrink-0 items-center gap-2 border-b border-divider px-3 py-2.5">
              <Search className="h-4 w-4 shrink-0 text-text-secondary" aria-hidden="true" />
              <input
                ref={inputRef}
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                onKeyDown={handleInputKeyDown}
                placeholder="Search tasks, events, projects, habits…"
                className="flex-1 bg-transparent text-sm text-text-primary outline-none placeholder:text-text-secondary"
              />
              <Dialog.Close asChild>
                <button aria-label="Close" className="shrink-0 rounded-leo-sm p-1 text-text-secondary hover:bg-surface-elevated">
                  <X className="h-4 w-4" />
                </button>
              </Dialog.Close>
            </div>

            <div className="min-h-0 flex-1 overflow-y-auto p-1.5">
              {query.trim() === '' && <p className="p-3 text-sm text-text-secondary">Type to search everything in LEO.</p>}

              {query.trim() !== '' && flatResults.length === 0 && <p className="p-3 text-sm text-text-secondary">No results for "{query}".</p>}

              {results.items.length > 0 && (
                <ResultGroup label="Tasks & events">
                  {results.items.map((r) => {
                    const globalIndex = flatResults.indexOf(r)
                    const Icon = ICONS[completionIconFor(r.item)]
                    return (
                      <ResultRow key={r.item.id} active={globalIndex === activeIndex} onClick={() => selectResult(r)} onMouseEnter={() => setActiveIndex(globalIndex)}>
                        <Icon className="h-4 w-4 shrink-0 text-text-secondary" aria-hidden="true" />
                        <span className="flex-1 truncate text-sm text-text-primary">{r.item.title}</span>
                        <span className="shrink-0 text-xs text-text-secondary">
                          {kindLabel(r.item.kind)}
                          {secondaryLineFor(r.item) ? ` · ${secondaryLineFor(r.item)}` : ''}
                        </span>
                      </ResultRow>
                    )
                  })}
                </ResultGroup>
              )}

              {results.projects.length > 0 && (
                <ResultGroup label="Projects">
                  {results.projects.map((r) => {
                    const globalIndex = flatResults.indexOf(r)
                    return (
                      <ResultRow key={r.tag.id} active={globalIndex === activeIndex} onClick={() => selectResult(r)} onMouseEnter={() => setActiveIndex(globalIndex)}>
                        <FolderKanban className="h-4 w-4 shrink-0 text-text-secondary" aria-hidden="true" />
                        <TagChip tag={r.tag} />
                        <span className="ml-auto shrink-0 text-xs text-text-secondary">{r.count} item{r.count === 1 ? '' : 's'}</span>
                      </ResultRow>
                    )
                  })}
                </ResultGroup>
              )}

              {results.habits.length > 0 && (
                <ResultGroup label="Habits">
                  {results.habits.map((r) => {
                    const globalIndex = flatResults.indexOf(r)
                    return (
                      <ResultRow key={r.habit.id} active={globalIndex === activeIndex} onClick={() => selectResult(r)} onMouseEnter={() => setActiveIndex(globalIndex)}>
                        <Repeat className="h-4 w-4 shrink-0 text-text-secondary" aria-hidden="true" />
                        <span className="flex-1 truncate text-sm text-text-primary">{r.habit.name}</span>
                      </ResultRow>
                    )
                  })}
                </ResultGroup>
              )}
            </div>
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>

      {openItem && <ItemDetailPanel item={openItem} onClose={() => setOpenItem(undefined)} />}
    </>
  )
}

function ResultGroup({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="mb-1">
      <p className="px-2 py-1 text-xs font-medium tracking-wide text-text-secondary uppercase">{label}</p>
      <ul className="flex flex-col gap-0.5">{children}</ul>
    </div>
  )
}

function ResultRow({
  active,
  onClick,
  onMouseEnter,
  children,
}: {
  active: boolean
  onClick: () => void
  onMouseEnter: () => void
  children: React.ReactNode
}) {
  return (
    <li>
      <button
        type="button"
        onClick={onClick}
        onMouseEnter={onMouseEnter}
        className={cn('flex w-full items-center gap-2 rounded-leo-sm px-2 py-1.5 text-left', active ? 'bg-accent-muted' : 'hover:bg-surface-elevated')}
      >
        {children}
      </button>
    </li>
  )
}
