import { anchorSortDate } from '@/wire/anchor'
import type { DomainItem, ItemKind } from '@/domain/types'

/**
 * Port of LEO/DesignSystem/Components/ItemRow.swift's per-kind display
 * logic — completion icon choice, the relative-time/location/kcal
 * secondary line, and the type label used in accessibility text. This is
 * the row component every native platform (iOS, Mac) shares across Today,
 * Inbox, and Habits; the web app had no equivalent, which was a big part
 * of why its item lists read as flat and undifferentiated.
 */

/** Lucide icon name to render for this item's completion state — see ItemRow.tsx for the actual <Icon> lookup. */
export type CompletionIconKind =
  | 'bell' | 'bellOff'
  | 'circleDot' | 'circleFilled'
  | 'calendar' | 'calendarCheck'
  | 'dumbbell'
  | 'utensils'
  | 'checkCircle' | 'circle'

export function completionIconFor(item: DomainItem): CompletionIconKind {
  const done = item.completion.type !== 'open'
  switch (item.kind) {
    case 'alarm':
      return done ? 'bellOff' : 'bell'
    case 'habitInstance':
      return done ? 'circleFilled' : 'circleDot'
    case 'event':
      return done ? 'calendarCheck' : 'calendar'
    case 'workout':
      return done ? 'dumbbell' : 'circle'
    case 'meal':
      return done ? 'utensils' : 'circle'
    default:
      return done ? 'checkCircle' : 'circle'
  }
}

function formatRelative(target: Date, now: Date): string {
  const diffMs = target.getTime() - now.getTime()
  const diffMin = Math.round(diffMs / 60_000)
  const abs = Math.abs(diffMin)
  if (abs < 1) return 'now'
  if (abs < 60) return diffMin > 0 ? `in ${abs} min` : `${abs} min ago`
  const diffHr = Math.round(diffMin / 60)
  if (Math.abs(diffHr) < 24) return diffHr > 0 ? `in ${diffHr}h` : `${Math.abs(diffHr)}h ago`
  const diffDay = Math.round(diffHr / 24)
  return diffDay > 0 ? `in ${diffDay}d` : `${Math.abs(diffDay)}d ago`
}

function formatTime(d: Date): string {
  return d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
}

/** The secondary line under an item's title — time/location/kcal, contextual per kind. Port of ItemRow.swift's secondaryParts. */
export function secondaryLineFor(item: DomainItem, now: Date = new Date()): string | undefined {
  const parts: string[] = []

  if (item.anchor.type === 'dueAt') {
    parts.push(`Due ${formatRelative(new Date(item.anchor.date), now)}`)
  } else if (item.anchor.type === 'timeBlock') {
    const start = new Date(item.anchor.start)
    const end = new Date(item.anchor.end)
    const isAllDay = start.getHours() === 0 && start.getMinutes() === 0 && end.getTime() - start.getTime() >= 23 * 3600_000
    parts.push(isAllDay ? 'All day' : `${formatTime(start)} – ${formatTime(end)}`)
  } else if (item.anchor.type === 'point') {
    parts.push(formatTime(new Date(item.anchor.date)))
  }

  if (item.kind === 'event' && item.location) parts.push(`· ${item.location}`)
  if (item.kind === 'habitInstance') parts.push('· Habit')
  if (item.kind === 'workout') parts.push(`· ~${item.estimatedKcal} kcal`)
  if (item.kind === 'meal') parts.push(`· ${item.actualKcal ?? item.targetKcal} kcal`)

  return parts.length > 0 ? parts.join(' ') : undefined
}

const KIND_LABELS: Record<ItemKind, string> = {
  task: 'Task',
  event: 'Event',
  reminder: 'Reminder',
  alarm: 'Alarm',
  habitInstance: 'Habit',
  workout: 'Workout',
  meal: 'Meal',
}

export function kindLabel(kind: ItemKind): string {
  return KIND_LABELS[kind]
}

/** Full accessible description, port of ItemRow.swift's accessibilityLabel. */
export function accessibleItemLabel(item: DomainItem): string {
  const parts = [kindLabel(item.kind), item.title]
  const sortDate = anchorSortDate(item.anchor)
  if (sortDate) {
    if (item.anchor.type === 'dueAt') parts.push(`due ${sortDate.toLocaleString()}`)
    else parts.push(`at ${formatTime(sortDate)}`)
  }
  if (item.importance >= 2) parts.push(item.importance === 3 ? 'urgent' : 'high priority')
  if (item.completion.type !== 'open') parts.push('completed')
  return parts.join(', ')
}
