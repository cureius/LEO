import { anchorSortDate } from '@/wire/anchor'
import type { HabitInstanceItem } from '@/domain/types'

/**
 * Simplified streak calculation — NOT a port of the native `StreakEngine`
 * (which factors in each habit's `forgiveness` rule: allowed misses per
 * week, or a minimum completion percentage). This counts strictly
 * consecutive completed days working backward from today and stops at the
 * first gap, which is easy to reason about and honest about what it does,
 * but will read a lower streak than native for a habit with forgiveness
 * configured. A closer port is future work if that divergence matters.
 */
export function currentStreakDays(instances: HabitInstanceItem[], today: Date = new Date()): number {
  const completedDays = new Set<string>()
  for (const instance of instances) {
    if (instance.completion.type !== 'completed') continue
    const d = anchorSortDate(instance.anchor)
    if (!d) continue
    completedDays.add(new Date(d.getFullYear(), d.getMonth(), d.getDate()).toDateString())
  }

  let streak = 0
  const cursor = new Date(today.getFullYear(), today.getMonth(), today.getDate())
  // Today itself may not be completed yet — don't let that break the streak;
  // start counting from yesterday if today has no completion.
  if (!completedDays.has(cursor.toDateString())) {
    cursor.setDate(cursor.getDate() - 1)
  }
  while (completedDays.has(cursor.toDateString())) {
    streak++
    cursor.setDate(cursor.getDate() - 1)
  }
  return streak
}
