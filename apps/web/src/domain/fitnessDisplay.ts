import { EXERCISE_CATALOG, RECIPE_CATALOG } from '@/ai/tools/fitnessCatalog'

const EXERCISE_NAMES: Record<string, string> = Object.fromEntries(EXERCISE_CATALOG.map((e) => [e.id, e.name]))
const RECIPE_NAMES: Record<string, string> = Object.fromEntries(RECIPE_CATALOG.map((r) => [r.id, r.name]))

/** Falls back to the raw id — the bundled catalog is a small placeholder (see fitnessCatalog.ts), so
 *  ids created elsewhere (native app's fuller library, or future catalog entries) won't always resolve. */
export function exerciseName(id: string): string {
  return EXERCISE_NAMES[id] ?? id
}
export function recipeName(id: string): string {
  return RECIPE_NAMES[id] ?? id
}

export function formatDayHeading(date: Date | null, today: Date = new Date()): string {
  if (!date) return 'Unscheduled'
  const startOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate())
  const diffDays = Math.round((date.getTime() - startOfToday.getTime()) / 86_400_000)
  if (diffDays === 0) return 'Today'
  if (diffDays === -1) return 'Yesterday'
  if (diffDays === 1) return 'Tomorrow'
  return date.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric', year: date.getFullYear() !== today.getFullYear() ? 'numeric' : undefined })
}
