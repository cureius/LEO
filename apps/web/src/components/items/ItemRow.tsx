import { useState, type DragEvent } from 'react'
import { Bell, BellOff, Calendar, CalendarCheck, CheckCircle2, Circle, Dumbbell, UtensilsCrossed } from 'lucide-react'
import { toggleComplete } from '@/sync/mutations'
import { isExternallyManaged } from '@/wire/items'
import { accessibleItemLabel, completionIconFor, secondaryLineFor, type CompletionIconKind } from '@/domain/itemDisplay'
import { Chip } from '@/components/ui/Chip'
import { TagChip } from '@/components/ui/TagChip'
import { Checkbox } from '@/components/ui/checkbox'
import { ItemDetailPanel } from './ItemDetailPanel'
import { cn } from '@/lib/utils'
import { useSyncStore } from '@/sync/store'
import type { DomainItem } from '@/domain/types'

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

/**
 * Port of LEO/DesignSystem/Components/ItemRow.swift, the row shared by
 * Today/Inbox/Habits on every native platform: a kind-specific completion
 * icon (not a generic checkbox), a relative-time/location/kcal secondary
 * line, importance + tag chips, and the whole row opens a detail view on
 * click — none of which the original web build had.
 */
type Props = {
  item: DomainItem
  selectMode?: boolean
  selected?: boolean
  onToggleSelect?: () => void
  /** Opt-in only — every other caller (Today, Inbox, Habits) renders this
   *  with neither prop set, so drag never activates outside ProjectsPage. */
  draggable?: boolean
  onDragStart?: (e: DragEvent<HTMLLIElement>) => void
  onDragEnd?: (e: DragEvent<HTMLLIElement>) => void
  /** e.g. dimming the row currently being dragged (ProjectsPage). */
  className?: string
  /** Default true. ProjectsPage sets this false — the row already sits
   *  inside a column labeled with its project, so repeating that project's
   *  own tag chip next to every single task in it is pure redundancy (any
   *  OTHER tags the item carries are hidden too, not just the current
   *  project's, since there's no reliable way to know from here which tag
   *  is "the" one driving this column vs. a genuinely separate one). */
  showTags?: boolean
  /** Default true. Inbox's kanban board sets this false — the row already
   *  sits in a column labeled Urgent/High/Normal/Low, so the Urgent/High
   *  chip repeats what the column itself already says. */
  showImportance?: boolean
}

export function ItemRow({
  item,
  selectMode = false,
  selected = false,
  onToggleSelect,
  draggable = false,
  onDragStart,
  onDragEnd,
  className,
  showTags = true,
  showImportance = true,
}: Props) {
  const [detailOpen, setDetailOpen] = useState(false)
  const readOnly = isExternallyManaged(item)
  const done = item.completion.type !== 'open'
  const Icon = ICONS[completionIconFor(item)]
  const secondary = secondaryLineFor(item)
  const tags = 'tags' in item ? item.tags : []
  // Only set for items pulled in from a recurring Google Calendar series
  // (see google/sync.ts) — purely a link-table lookup, doesn't touch the
  // item's own wire format at all.
  const isRecurring = useSyncStore((s) => !!s.googleLinks.get(item.id)?.googleRecurringEventId)
  const secondaryParts = [secondary, isRecurring ? '↻ Repeats' : undefined, readOnly ? 'Synced from Calendar/Reminders' : undefined].filter(
    (part): part is string => Boolean(part),
  )

  return (
    <>
      <li
        draggable={draggable}
        onDragStart={onDragStart}
        onDragEnd={onDragEnd}
        className={cn(
          'flex items-center gap-3 rounded-leo-md border border-divider bg-surface px-3 py-2.5 transition-colors hover:border-accent/40',
          draggable && 'cursor-grab active:cursor-grabbing',
          className,
        )}
      >
        {selectMode ? (
          <Checkbox checked={selected} onCheckedChange={() => onToggleSelect?.()} aria-label={`Select "${item.title}"`} className="ml-0.5 shrink-0" />
        ) : (
          <button
            type="button"
            onClick={() => !readOnly && void toggleComplete(item)}
            disabled={readOnly}
            aria-label={done ? `Mark "${item.title}" not done` : `Mark "${item.title}" done`}
            className={`shrink-0 rounded-full p-2 ${readOnly ? 'opacity-40' : 'hover:bg-surface-elevated'}`}
          >
            <Icon className={`h-5 w-5 ${done ? 'text-success' : 'text-text-secondary'}`} strokeWidth={done ? 2.5 : 2} />
          </button>
        )}

        <button
          type="button"
          onClick={() => setDetailOpen(true)}
          className="flex flex-1 flex-col items-start gap-0.5 text-left"
          aria-label={accessibleItemLabel(item)}
        >
          <span className={`text-sm font-medium text-text-primary ${done ? 'text-text-secondary line-through' : ''}`}>
            {item.title}
          </span>
          {secondaryParts.length > 0 && <span className="text-xs text-text-secondary">{secondaryParts.join(' · ')}</span>}
        </button>

        <div className="flex shrink-0 items-center gap-1">
          {showImportance && item.importance === 3 && <Chip tone="danger">Urgent</Chip>}
          {showImportance && item.importance === 2 && <Chip tone="warning">High</Chip>}
          {showTags && tags.slice(0, 2).map((tag) => <TagChip key={tag.id} tag={tag} />)}
          {showTags && tags.length > 2 && <span className="text-xs text-text-secondary">+{tags.length - 2}</span>}
        </div>
      </li>

      {detailOpen && <ItemDetailPanel item={item} onClose={() => setDetailOpen(false)} />}
    </>
  )
}
