import { describe, expect, it } from 'vitest'
import { itemHasProjectTag, matchesRule } from '../automationRules'
import type { AutomationRule, RuleCondition } from '../automationRules'
import type { EventItem, TaskItem } from '@/domain/types'

const base = {
  id: 'x', title: 'Standup', createdAt: new Date(), updatedAt: new Date(), importance: 1, tags: [],
}

function group(conditions: RuleCondition[]) {
  return { id: crypto.randomUUID(), conditions }
}

function officeRule(overrides: Partial<AutomationRule> = {}): AutomationRule {
  return {
    id: 'r1',
    name: 'Office',
    enabled: true,
    conditionGroups: [group([{ field: 'attendeeEmail', contains: '@mycompany.com' }])],
    targetProjectName: 'Office',
    targetProjectColor: 'blue',
    createdAt: new Date(),
    updatedAt: new Date(),
    ...overrides,
  }
}

describe('matchesRule — single group (AND within group)', () => {
  it('matches an event whose attendee email contains the rule suffix', () => {
    const event: EventItem = { ...base, kind: 'event', anchor: { type: 'untimed' }, completion: { type: 'open' }, attendees: ['boss@mycompany.com'] }
    expect(matchesRule(event, officeRule())).toBe(true)
  })

  it('is case-insensitive', () => {
    const event: EventItem = { ...base, kind: 'event', anchor: { type: 'untimed' }, completion: { type: 'open' }, attendees: ['Boss@MyCompany.com'] }
    expect(matchesRule(event, officeRule())).toBe(true)
  })

  it('does not match when no attendee has the suffix', () => {
    const event: EventItem = { ...base, kind: 'event', anchor: { type: 'untimed' }, completion: { type: 'open' }, attendees: ['friend@gmail.com'] }
    expect(matchesRule(event, officeRule())).toBe(false)
  })

  it('a non-event item never matches an attendeeEmail condition', () => {
    const task: TaskItem = { ...base, kind: 'task', anchor: { type: 'untimed' }, completion: { type: 'open' } }
    expect(matchesRule(task, officeRule())).toBe(false)
  })

  it('requires every condition within a group to match (AND)', () => {
    const rule = officeRule({ conditionGroups: [group([{ field: 'attendeeEmail', contains: '@mycompany.com' }, { field: 'title', contains: 'standup' }])] })
    const matchingTitle: EventItem = { ...base, title: 'Daily Standup', kind: 'event', anchor: { type: 'untimed' }, completion: { type: 'open' }, attendees: ['boss@mycompany.com'] }
    const wrongTitle: EventItem = { ...base, title: 'Retro', kind: 'event', anchor: { type: 'untimed' }, completion: { type: 'open' }, attendees: ['boss@mycompany.com'] }
    expect(matchesRule(matchingTitle, rule)).toBe(true)
    expect(matchesRule(wrongTitle, rule)).toBe(false)
  })

  it('a rule with zero groups matches nothing', () => {
    const event: EventItem = { ...base, kind: 'event', anchor: { type: 'untimed' }, completion: { type: 'open' }, attendees: ['boss@mycompany.com'] }
    expect(matchesRule(event, officeRule({ conditionGroups: [] }))).toBe(false)
  })

  it('a group with zero conditions matches nothing', () => {
    const event: EventItem = { ...base, kind: 'event', anchor: { type: 'untimed' }, completion: { type: 'open' }, attendees: ['boss@mycompany.com'] }
    expect(matchesRule(event, officeRule({ conditionGroups: [group([])] }))).toBe(false)
  })

  it('an empty/whitespace-only condition value never matches', () => {
    const event: EventItem = { ...base, kind: 'event', anchor: { type: 'untimed' }, completion: { type: 'open' }, attendees: ['boss@mycompany.com'] }
    expect(matchesRule(event, officeRule({ conditionGroups: [group([{ field: 'attendeeEmail', contains: '   ' }])] }))).toBe(false)
  })
})

describe('matchesRule — multiple groups (OR across groups)', () => {
  function fitnessRule(): AutomationRule {
    return officeRule({
      name: 'Fitness',
      targetProjectName: 'Fitness',
      conditionGroups: [group([{ field: 'title', contains: 'gym' }]), group([{ field: 'title', contains: 'yoga' }])],
    })
  }

  it('matches when only the first group matches', () => {
    const task: TaskItem = { ...base, title: 'Gym session', kind: 'task', anchor: { type: 'untimed' }, completion: { type: 'open' } }
    expect(matchesRule(task, fitnessRule())).toBe(true)
  })

  it('matches when only the second group matches', () => {
    const task: TaskItem = { ...base, title: 'Yoga class', kind: 'task', anchor: { type: 'untimed' }, completion: { type: 'open' } }
    expect(matchesRule(task, fitnessRule())).toBe(true)
  })

  it('does not match when neither group matches', () => {
    const task: TaskItem = { ...base, title: 'Grocery run', kind: 'task', anchor: { type: 'untimed' }, completion: { type: 'open' } }
    expect(matchesRule(task, fitnessRule())).toBe(false)
  })

  it('a fully-satisfied group is enough even if another group is only partially satisfied', () => {
    const rule = officeRule({
      conditionGroups: [
        group([{ field: 'attendeeEmail', contains: '@mycompany.com' }, { field: 'title', contains: 'never-matches' }]),
        group([{ field: 'title', contains: 'standup' }]),
      ],
    })
    const item: EventItem = { ...base, title: 'Daily Standup', kind: 'event', anchor: { type: 'untimed' }, completion: { type: 'open' }, attendees: [] }
    expect(matchesRule(item, rule)).toBe(true)
  })
})

describe('itemHasProjectTag', () => {
  it('true when a tag with that name is present', () => {
    const task: TaskItem = { ...base, kind: 'task', anchor: { type: 'untimed' }, completion: { type: 'open' }, tags: [{ id: 't1', name: 'Office', colorRaw: 'blue' }] }
    expect(itemHasProjectTag(task, 'Office')).toBe(true)
  })

  it('false when absent', () => {
    const task: TaskItem = { ...base, kind: 'task', anchor: { type: 'untimed' }, completion: { type: 'open' } }
    expect(itemHasProjectTag(task, 'Office')).toBe(false)
  })
})
