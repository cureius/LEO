import { describe, expect, it } from 'vitest'
import { currentStreakDays } from '../streak'
import type { HabitInstanceItem } from '@/domain/types'

function instance(daysAgo: number, completed: boolean): HabitInstanceItem {
  const date = new Date()
  date.setDate(date.getDate() - daysAgo)
  return {
    kind: 'habitInstance', id: `d${daysAgo}`, title: 'x', createdAt: date, updatedAt: date,
    importance: 1, anchor: { type: 'point', date: date.toISOString() },
    completion: completed ? { type: 'completed', date: date.toISOString() } : { type: 'open' },
    habitID: 'h1',
  }
}

describe('currentStreakDays', () => {
  it('is 0 with no instances', () => {
    expect(currentStreakDays([])).toBe(0)
  })

  it('counts today + consecutive prior completed days', () => {
    const instances = [instance(0, true), instance(1, true), instance(2, true)]
    expect(currentStreakDays(instances)).toBe(3)
  })

  it('does not break the streak just because today is not yet completed', () => {
    const instances = [instance(0, false), instance(1, true), instance(2, true)]
    expect(currentStreakDays(instances)).toBe(2)
  })

  it('stops counting at the first gap', () => {
    const instances = [instance(0, true), instance(1, true), instance(3, true)] // gap at day 2
    expect(currentStreakDays(instances)).toBe(2)
  })

  it('is 0 if the most recent completion was more than 1 day ago', () => {
    const instances = [instance(3, true)]
    expect(currentStreakDays(instances)).toBe(0)
  })
})
