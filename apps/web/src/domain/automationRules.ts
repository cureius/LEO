import type { DomainItem, TagColor } from './types'

/**
 * A small rules engine for auto-filing items into a project: a rule is one
 * or more condition GROUPS checked against an item's attendees / title /
 * notes / location. A group matches only if ALL of its conditions match
 * (AND); a rule matches if ANY of its groups match (OR) — i.e. disjunctive
 * normal form, the same "match ALL of / match ANY of" shape most rule
 * builders use (Zapier filters, mail client rules) rather than free-form
 * nested boolean expressions, which would need a much heavier UI for
 * marginal extra power. Deliberately general (not "Office" specific) so a
 * user can define whatever rules they want — e.g. "attendee email contains
 * @mycompany.com" -> "Office", or "(title contains gym) OR (title contains
 * yoga)" -> "Fitness".
 */

export type RuleConditionField = 'attendeeEmail' | 'title' | 'notes' | 'location'

export type RuleCondition = {
  field: RuleConditionField
  /** Case-insensitive substring match — e.g. field: 'attendeeEmail',
   *  contains: '@acme.com' matches any attendee whose email contains that
   *  suffix, which is what makes "email suffix" matching work without a
   *  dedicated domain-equality field. */
  contains: string
}

export type RuleConditionGroup = {
  /** Client-generated, stable only for the lifetime of an edit session —
   *  React list keys and per-group add/remove in RulesDialog, nothing more. */
  id: string
  /** All conditions in a group must match (AND). */
  conditions: RuleCondition[]
}

export type AutomationRule = {
  id: string
  name: string
  enabled: boolean
  /** A rule matches if ANY group matches (OR across groups). */
  conditionGroups: RuleConditionGroup[]
  targetProjectName: string
  targetProjectColor: TagColor
  createdAt: Date
  updatedAt: Date
}

function fieldValues(item: DomainItem, field: RuleConditionField): string[] {
  switch (field) {
    case 'attendeeEmail':
      return item.kind === 'event' ? item.attendees : []
    case 'title':
      return [item.title]
    case 'notes':
      return item.notes ? [item.notes] : []
    case 'location':
      return item.kind === 'event' && item.location ? [item.location] : []
  }
}

function conditionMatches(item: DomainItem, cond: RuleCondition): boolean {
  const needle = cond.contains.trim().toLowerCase()
  if (!needle) return false
  return fieldValues(item, cond.field).some((v) => v.toLowerCase().includes(needle))
}

/** A group with no conditions matches nothing — same "not configured yet
 *  shouldn't mean match everything" reasoning as an empty rule below. */
function groupMatches(item: DomainItem, group: RuleConditionGroup): boolean {
  if (group.conditions.length === 0) return false
  return group.conditions.every((cond) => conditionMatches(item, cond))
}

/** A rule with no groups (or only empty groups) matches nothing. Vacuous
 *  truth would otherwise make "haven't configured any conditions yet"
 *  silently tag every single item. */
export function matchesRule(item: DomainItem, rule: AutomationRule): boolean {
  if (rule.conditionGroups.length === 0) return false
  return rule.conditionGroups.some((group) => groupMatches(item, group))
}

export function itemHasProjectTag(item: DomainItem, projectName: string): boolean {
  return 'tags' in item && item.tags.some((t) => t.name === projectName)
}
