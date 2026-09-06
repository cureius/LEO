import { anchorSortDate, completionCompletedAt } from '@/wire/anchor'
import { currentStreakDays } from './streak'
import type { DomainItem, Habit, HabitInstanceItem, ItemKind, TagColor } from './types'

/**
 * Pure aggregation over the already-loaded items/habits in the store — no
 * network calls, nothing async, so it's cheap to recompute in a useMemo on
 * every store change and easy to unit test (see __tests__). DashboardPage
 * is the only caller; this module just owns "what do the numbers mean."
 */

const IMPORTANCE_LABELS = ['Low', 'Normal', 'High', 'Urgent']

export type KindBreakdown = { kind: ItemKind; count: number }
export type ImportanceBreakdown = { importance: number; label: string; count: number }
export type ProjectBreakdown = {
  name: string
  color: TagColor
  openCount: number
  totalCount: number
  completedCount: number
  /** % of this project's items (open + completed) that are completed, 0-100. */
  completionRate: number
}
export type DayCount = { date: string; label: string; count: number }
export type DayHours = { date: string; label: string; hours: number }
export type HabitStreak = { name: string; streak: number }

export type DashboardStats = {
  openCount: number
  completedThisWeek: number
  overdueCount: number
  /** % of items whose sortDate fell in the last 30 days that ended up completed. */
  completionRate30d: number
  activeHabitCount: number
  bestStreak: number
  /** Oldest → newest, one entry per day from the 1st of the current month through today. */
  completionsByDay: DayCount[]
  /** Today → 6 days out, 7 entries. */
  scheduledHoursByDay: DayHours[]
  byKind: KindBreakdown[]
  byImportance: ImportanceBreakdown[]
  /** Top 8 by open count, descending. */
  byProject: ProjectBreakdown[]
  /** Descending by streak. */
  habitStreaks: HabitStreak[]
}

function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}

function dayLabel(d: Date): string {
  return d.toLocaleDateString(undefined, { weekday: 'short' })
}

export function computeDashboardStats(items: DomainItem[], habits: Habit[], now: Date = new Date()): DashboardStats {
  const today = startOfDay(now)
  const nonHabitItems = items.filter((i): i is Exclude<DomainItem, HabitInstanceItem> => i.kind !== 'habitInstance')
  const open = nonHabitItems.filter((i) => i.completion.type === 'open')

  const overdueCount = open.filter((i) => {
    const d = anchorSortDate(i.anchor)
    return d ? d < now : false
  }).length

  const weekAgo = new Date(today)
  weekAgo.setDate(weekAgo.getDate() - 6)
  const completedThisWeek = nonHabitItems.filter((i) => {
    const d = completionCompletedAt(i.completion)
    return d ? d >= weekAgo : false
  }).length

  const windowStart = new Date(today)
  windowStart.setDate(windowStart.getDate() - 29)
  const due30 = nonHabitItems.filter((i) => {
    const d = anchorSortDate(i.anchor)
    return d ? d >= windowStart && d <= now : false
  })
  const completionRate30d =
    due30.length === 0 ? 0 : Math.round((due30.filter((i) => i.completion.type === 'completed').length / due30.length) * 100)

  const completionCountByDay = new Map<string, number>()
  for (const item of items) {
    const d = completionCompletedAt(item.completion)
    if (!d) continue
    const key = startOfDay(d).toDateString()
    completionCountByDay.set(key, (completionCountByDay.get(key) ?? 0) + 1)
  }
  const completionsByDay: DayCount[] = []
  const monthStart = new Date(today.getFullYear(), today.getMonth(), 1)
  for (let day = monthStart; day <= today; day.setDate(day.getDate() + 1)) {
    completionsByDay.push({ date: day.toDateString(), label: dayLabel(day), count: completionCountByDay.get(day.toDateString()) ?? 0 })
  }

  const scheduledHoursByDayMap = new Map<string, number>()
  for (const item of open) {
    if (item.anchor.type !== 'timeBlock') continue
    const start = new Date(item.anchor.start)
    const end = new Date(item.anchor.end)
    const key = startOfDay(start).toDateString()
    const hours = Math.max(0, (end.getTime() - start.getTime()) / 3_600_000)
    scheduledHoursByDayMap.set(key, (scheduledHoursByDayMap.get(key) ?? 0) + hours)
  }
  const scheduledHoursByDay: DayHours[] = []
  for (let i = 0; i < 7; i++) {
    const day = new Date(today)
    day.setDate(day.getDate() + i)
    const hours = Math.round((scheduledHoursByDayMap.get(day.toDateString()) ?? 0) * 10) / 10
    scheduledHoursByDay.push({ date: day.toDateString(), label: dayLabel(day), hours })
  }

  const kindCounts = new Map<ItemKind, number>()
  for (const item of open) kindCounts.set(item.kind, (kindCounts.get(item.kind) ?? 0) + 1)
  const byKind: KindBreakdown[] = Array.from(kindCounts.entries())
    .map(([kind, count]) => ({ kind, count }))
    .sort((a, b) => b.count - a.count)

  const importanceCounts = [0, 0, 0, 0]
  for (const item of open) {
    if (item.importance >= 0 && item.importance <= 3) importanceCounts[item.importance]++
  }
  const byImportance: ImportanceBreakdown[] = importanceCounts.map((count, importance) => ({
    importance,
    label: IMPORTANCE_LABELS[importance],
    count,
  }))

  // Walks every item (not just open ones) so a project that's fully wrapped
  // up — every item completed — still shows up with its real completion
  // rate instead of vanishing from the list entirely.
  const projectMap = new Map<string, ProjectBreakdown>()
  for (const item of nonHabitItems) {
    if (!('tags' in item)) continue
    for (const tag of item.tags) {
      const entry = projectMap.get(tag.name) ?? { name: tag.name, color: tag.colorRaw, openCount: 0, totalCount: 0, completedCount: 0, completionRate: 0 }
      entry.totalCount++
      if (item.completion.type === 'open') entry.openCount++
      if (item.completion.type === 'completed') entry.completedCount++
      projectMap.set(tag.name, entry)
    }
  }
  const byProject = Array.from(projectMap.values())
    .map((p) => ({ ...p, completionRate: Math.round((p.completedCount / p.totalCount) * 100) }))
    .sort((a, b) => b.openCount - a.openCount)
    .slice(0, 8)

  const instancesByHabit = new Map<string, HabitInstanceItem[]>()
  for (const item of items) {
    if (item.kind !== 'habitInstance') continue
    const list = instancesByHabit.get(item.habitID)
    if (list) list.push(item)
    else instancesByHabit.set(item.habitID, [item])
  }
  const activeHabits = habits.filter((h) => !h.isArchived)
  const habitStreaks: HabitStreak[] = activeHabits
    .map((h) => ({ name: h.name, streak: currentStreakDays(instancesByHabit.get(h.id) ?? [], now) }))
    .sort((a, b) => b.streak - a.streak)
  const bestStreak = habitStreaks.reduce((max, h) => Math.max(max, h.streak), 0)

  return {
    openCount: open.length,
    completedThisWeek,
    overdueCount,
    completionRate30d,
    activeHabitCount: activeHabits.length,
    bestStreak,
    completionsByDay,
    scheduledHoursByDay,
    byKind,
    byImportance,
    byProject,
    habitStreaks,
  }
}
