import { describe, expect, it } from 'vitest'
import { toolActivityLabel } from '../toolDisplay'

describe('toolActivityLabel', () => {
  it('returns a friendly label for every registered tool', () => {
    expect(toolActivityLabel('get_today')).toBe("Checking today's schedule")
    expect(toolActivityLabel('get_week')).toBe("Checking this week's schedule")
    expect(toolActivityLabel('propose_workout_plan')).toBe('Building a workout plan')
    expect(toolActivityLabel('get_fitness_items')).toBe('Checking all your workouts and meals')
    expect(toolActivityLabel('get_past_items')).toBe('Looking back through your history')
  })

  it('falls back to a humanized version of the raw tool name for anything unregistered', () => {
    expect(toolActivityLabel('some_new_tool')).toBe('Using some new tool')
  })
})
