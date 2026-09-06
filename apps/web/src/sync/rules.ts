import { supabase } from '@/lib/supabaseClient'
import { useSyncStore } from './store'
import { updateItem } from './mutations'
import { matchesRule } from '@/domain/automationRules'
import type { AutomationRule, RuleConditionGroup } from '@/domain/automationRules'
import type { DomainItem, TagColor } from '@/domain/types'

/**
 * CRUD + the actual rule runner for automation_rules — a web-only table
 * (see migration 0006's doc comment), so this mirrors google/links.ts's
 * self-contained style (direct Supabase calls + store updates) rather than
 * the fuller items/habits wire-format pipeline, which exists specifically
 * for tables shared with the native Swift app. Migration 0007 renamed the
 * flat `conditions` column to `condition_groups` when AND/OR group support
 * was added — no runtime backward-compat shim needed here since that
 * migration also reshaped the one existing row in place.
 */

type RuleRow = {
  id: string
  name: string
  enabled: boolean
  condition_groups: RuleConditionGroup[]
  target_project_name: string
  target_project_color: TagColor
  created_at: string
  updated_at: string
}

const SELECT_COLUMNS = 'id, name, enabled, condition_groups, target_project_name, target_project_color, created_at, updated_at'

function decodeRuleRow(row: RuleRow): AutomationRule {
  return {
    id: row.id,
    name: row.name,
    enabled: row.enabled,
    conditionGroups: row.condition_groups,
    targetProjectName: row.target_project_name,
    targetProjectColor: row.target_project_color,
    createdAt: new Date(row.created_at),
    updatedAt: new Date(row.updated_at),
  }
}

export async function loadRules(): Promise<void> {
  const { data, error } = await supabase.from('automation_rules').select(SELECT_COLUMNS).is('deleted_at', null)
  if (error) throw error
  const store = useSyncStore.getState()
  for (const row of data as RuleRow[]) store.upsertRule(decodeRuleRow(row))
}

async function currentUserId(): Promise<string> {
  const { data } = await supabase.auth.getSession()
  const userId = data.session?.user.id
  if (!userId) throw new Error('Not signed in')
  return userId
}

export type NewRule = {
  name: string
  enabled: boolean
  conditionGroups: RuleConditionGroup[]
  targetProjectName: string
  targetProjectColor: TagColor
}

export async function createRule(rule: NewRule): Promise<void> {
  const userId = await currentUserId()
  const { data, error } = await supabase
    .from('automation_rules')
    .insert({
      user_id: userId,
      name: rule.name,
      enabled: rule.enabled,
      condition_groups: rule.conditionGroups,
      target_project_name: rule.targetProjectName,
      target_project_color: rule.targetProjectColor,
    })
    .select(SELECT_COLUMNS)
    .single()
  if (error) throw error
  useSyncStore.getState().upsertRule(decodeRuleRow(data as RuleRow))
}

export async function updateRule(id: string, patch: Partial<NewRule>): Promise<void> {
  const payload: Record<string, unknown> = {}
  if (patch.name !== undefined) payload.name = patch.name
  if (patch.enabled !== undefined) payload.enabled = patch.enabled
  if (patch.conditionGroups !== undefined) payload.condition_groups = patch.conditionGroups
  if (patch.targetProjectName !== undefined) payload.target_project_name = patch.targetProjectName
  if (patch.targetProjectColor !== undefined) payload.target_project_color = patch.targetProjectColor

  const { data, error } = await supabase.from('automation_rules').update(payload).eq('id', id).select(SELECT_COLUMNS).single()
  if (error) throw error
  useSyncStore.getState().upsertRule(decodeRuleRow(data as RuleRow))
}

export async function deleteRule(id: string): Promise<void> {
  const { error } = await supabase.from('automation_rules').update({ deleted_at: new Date().toISOString() }).eq('id', id)
  if (error) throw error
  useSyncStore.getState().removeRule(id)
}

/** Applies every ENABLED rule to every item: for each item that matches a
 *  rule and doesn't already carry that rule's project tag, adds the tag.
 *  Never replaces/removes existing tags — a rule files an item INTO a
 *  project, unlike drag-and-drop's reassign-by-replacing semantics
 *  (domain/projects.ts's reassignItemToProject) — an automated background
 *  action silently stomping a user's manual categorization would be a much
 *  worse surprise than an item ending up in two projects at once. Returns
 *  how many items were actually changed, for the "Run rules now" button's
 *  toast. Safe to call repeatedly — already-tagged items are no-ops. */
export async function runRulesNow(items: DomainItem[], rules: AutomationRule[]): Promise<number> {
  const enabledRules = rules.filter((r) => r.enabled)
  if (enabledRules.length === 0) return 0

  const updates: DomainItem[] = []
  for (const item of items) {
    if (!('tags' in item)) continue
    const newTags = [...item.tags]
    let changed = false
    for (const rule of enabledRules) {
      if (newTags.some((t) => t.name === rule.targetProjectName)) continue
      if (!matchesRule(item, rule)) continue
      newTags.push({ id: crypto.randomUUID(), name: rule.targetProjectName, colorRaw: rule.targetProjectColor })
      changed = true
    }
    if (changed) updates.push({ ...item, tags: newTags })
  }

  await Promise.allSettled(updates.map((item) => updateItem(item)))
  return updates.length
}
