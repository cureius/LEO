import { useState } from 'react'
import * as Dialog from '@radix-ui/react-dialog'
import { toast } from 'sonner'
import { Pencil, Play, Plus, Trash2, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Checkbox } from '@/components/ui/checkbox'
import { ColorSwatchPicker } from '@/components/ui/ColorSwatchPicker'
import { TagChip } from '@/components/ui/TagChip'
import { createRule, deleteRule, runRulesNow, updateRule } from '@/sync/rules'
import { RESPONSIVE_DIALOG_CONTENT, RESPONSIVE_DIALOG_OVERLAY } from '@/components/ui/responsiveDialog'
import { cn } from '@/lib/utils'
import { TAG_COLORS } from '@/domain/tagColors'
import type { AutomationRule, RuleCondition, RuleConditionField, RuleConditionGroup } from '@/domain/automationRules'
import type { DomainItem, TagColor } from '@/domain/types'

/**
 * Automation rules management, opened from ProjectsPage's "Rules" button.
 * A rule is a name + one or more condition GROUPS (attendee email / title /
 * notes / location contains some text) + a target project — a rule matches
 * if ANY group matches (OR across groups), and a group matches only if ALL
 * its own conditions match (AND within the group). See
 * domain/automationRules.ts for the matching engine and sync/rules.ts for
 * "Run rules now"'s actual write behavior (adds, never replaces, tags).
 */

const FIELD_LABELS: Record<RuleConditionField, string> = {
  attendeeEmail: 'Attendee email contains',
  title: 'Title contains',
  notes: 'Notes contains',
  location: 'Location contains',
}
const FIELDS = Object.keys(FIELD_LABELS) as RuleConditionField[]

function emptyCondition(): RuleCondition {
  return { field: 'attendeeEmail', contains: '' }
}
function emptyGroup(): RuleConditionGroup {
  return { id: crypto.randomUUID(), conditions: [emptyCondition()] }
}

function ruleSummary(rule: AutomationRule): string {
  const totalConditions = rule.conditionGroups.reduce((sum, g) => sum + g.conditions.length, 0)
  const noun = `${totalConditions} condition${totalConditions === 1 ? '' : 's'}`
  return rule.conditionGroups.length > 1 ? `${rule.conditionGroups.length} groups (OR) · ${noun}` : noun
}

function RuleEditor({ rule, onDone }: { rule?: AutomationRule; onDone: () => void }) {
  const [name, setName] = useState(rule?.name ?? '')
  const [groups, setGroups] = useState<RuleConditionGroup[]>(rule && rule.conditionGroups.length > 0 ? rule.conditionGroups : [emptyGroup()])
  const [targetName, setTargetName] = useState(rule?.targetProjectName ?? '')
  const [targetColor, setTargetColor] = useState<TagColor>(rule?.targetProjectColor ?? TAG_COLORS[0])
  const [saving, setSaving] = useState(false)

  const cleanGroups = groups
    .map((g) => ({ ...g, conditions: g.conditions.filter((c) => c.contains.trim()) }))
    .filter((g) => g.conditions.length > 0)
  const valid = name.trim().length > 0 && targetName.trim().length > 0 && cleanGroups.length > 0

  function updateCondition(groupIdx: number, condIdx: number, patch: Partial<RuleCondition>) {
    setGroups((prev) =>
      prev.map((g, gi) => (gi !== groupIdx ? g : { ...g, conditions: g.conditions.map((c, ci) => (ci === condIdx ? { ...c, ...patch } : c)) })),
    )
  }

  /** Removing a group's last condition removes the whole group (nothing
   *  left for it to mean) — unless it's the only group left, in which case
   *  the remove button is simply disabled, mirroring the single-group
   *  minimum-of-one-condition rule from before groups existed. */
  function removeCondition(groupIdx: number, condIdx: number) {
    setGroups((prev) => {
      const group = prev[groupIdx]
      if (group.conditions.length > 1) {
        return prev.map((g, gi) => (gi !== groupIdx ? g : { ...g, conditions: g.conditions.filter((_, ci) => ci !== condIdx) }))
      }
      if (prev.length > 1) return prev.filter((_, gi) => gi !== groupIdx)
      return prev
    })
  }

  function addCondition(groupIdx: number) {
    setGroups((prev) => prev.map((g, gi) => (gi !== groupIdx ? g : { ...g, conditions: [...g.conditions, emptyCondition()] })))
  }

  function addGroup() {
    setGroups((prev) => [...prev, emptyGroup()])
  }

  function removeGroup(groupIdx: number) {
    setGroups((prev) => (prev.length > 1 ? prev.filter((_, gi) => gi !== groupIdx) : prev))
  }

  async function handleSave() {
    if (!valid) return
    setSaving(true)
    try {
      if (rule) {
        await updateRule(rule.id, { name: name.trim(), conditionGroups: cleanGroups, targetProjectName: targetName.trim(), targetProjectColor: targetColor })
      } else {
        await createRule({ name: name.trim(), enabled: true, conditionGroups: cleanGroups, targetProjectName: targetName.trim(), targetProjectColor: targetColor })
      }
      onDone()
    } catch (err) {
      toast.error("Couldn't save rule", { description: err instanceof Error ? err.message : String(err) })
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="rule-name">Rule name</Label>
        <Input id="rule-name" value={name} onChange={(e) => setName(e.target.value)} placeholder="Work meetings" autoFocus />
      </div>

      <div className="flex flex-col gap-1.5">
        <Label>Conditions — match any group below (OR); within a group, all conditions must match (AND)</Label>
        <div className="flex flex-col">
          {groups.map((group, gi) => (
            <div key={group.id}>
              {gi > 0 && (
                <div className="my-2 flex items-center gap-2">
                  <div className="h-px flex-1 bg-divider" />
                  <span className="text-[10px] font-semibold tracking-wide text-text-secondary uppercase">Or</span>
                  <div className="h-px flex-1 bg-divider" />
                </div>
              )}
              <div className="rounded-leo-md border border-divider p-2">
                <div className="flex flex-col gap-2">
                  {group.conditions.map((cond, ci) => (
                    <div key={ci} className="flex items-center gap-1.5">
                      <select
                        value={cond.field}
                        onChange={(e) => updateCondition(gi, ci, { field: e.target.value as RuleConditionField })}
                        className="h-9 shrink-0 rounded-leo-md border border-divider bg-surface px-2 text-base text-text-primary md:text-sm"
                      >
                        {FIELDS.map((f) => (
                          <option key={f} value={f}>
                            {FIELD_LABELS[f]}
                          </option>
                        ))}
                      </select>
                      <Input
                        value={cond.contains}
                        onChange={(e) => updateCondition(gi, ci, { contains: e.target.value })}
                        placeholder={cond.field === 'attendeeEmail' ? '@yourcompany.com' : 'text to match'}
                        className="flex-1"
                      />
                      <button
                        type="button"
                        onClick={() => removeCondition(gi, ci)}
                        disabled={groups.length === 1 && group.conditions.length === 1}
                        aria-label="Remove condition"
                        className="shrink-0 rounded-leo-sm p-1.5 text-text-secondary hover:bg-surface-elevated disabled:opacity-30"
                      >
                        <X className="h-3.5 w-3.5" />
                      </button>
                    </div>
                  ))}
                </div>
                <div className="mt-2 flex items-center justify-between">
                  <Button type="button" variant="ghost" size="sm" onClick={() => addCondition(gi)} className="gap-1.5 text-text-secondary">
                    <Plus className="h-3.5 w-3.5" aria-hidden="true" />
                    And condition
                  </Button>
                  {groups.length > 1 && (
                    <button
                      type="button"
                      onClick={() => removeGroup(gi)}
                      className="rounded-leo-sm px-2 py-1 text-xs text-text-secondary hover:bg-surface-elevated hover:text-danger"
                    >
                      Remove group
                    </button>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
        <Button type="button" variant="outline" size="sm" onClick={addGroup} className="w-fit gap-1.5">
          <Plus className="h-3.5 w-3.5" aria-hidden="true" />
          Or group
        </Button>
      </div>

      <div className="flex flex-col gap-1.5">
        <Label htmlFor="rule-target">Put matches in project</Label>
        <Input id="rule-target" value={targetName} onChange={(e) => setTargetName(e.target.value)} placeholder="Office" />
        <ColorSwatchPicker value={targetColor} onChange={setTargetColor} />
      </div>

      <div className="mt-1 flex justify-end gap-2">
        <Button type="button" variant="ghost" onClick={onDone}>
          Cancel
        </Button>
        <Button type="button" onClick={() => void handleSave()} disabled={!valid || saving}>
          {saving ? 'Saving…' : rule ? 'Save rule' : 'Create rule'}
        </Button>
      </div>
    </div>
  )
}

export function RulesDialog({ items, rules, onClose }: { items: DomainItem[]; rules: AutomationRule[]; onClose: () => void }) {
  const [editing, setEditing] = useState<AutomationRule | 'new' | null>(null)
  const [running, setRunning] = useState(false)

  async function handleRunNow() {
    setRunning(true)
    try {
      const count = await runRulesNow(items, rules)
      toast.success(count === 0 ? 'No new matches — everything already up to date.' : `Applied rules to ${count} item${count === 1 ? '' : 's'}.`)
    } catch (err) {
      toast.error("Couldn't run rules", { description: err instanceof Error ? err.message : String(err) })
    } finally {
      setRunning(false)
    }
  }

  return (
    <Dialog.Root open onOpenChange={(open) => !open && onClose()}>
      <Dialog.Portal>
        <Dialog.Overlay className={RESPONSIVE_DIALOG_OVERLAY} />
        <Dialog.Content className={cn(RESPONSIVE_DIALOG_CONTENT, 'sm:max-w-lg max-h-[85vh] overflow-y-auto bg-surface p-4 shadow-xl')}>
          <div className="mb-3 flex items-center justify-between">
            <Dialog.Title className="text-sm font-medium text-text-primary">
              {editing ? (editing === 'new' ? 'New rule' : 'Edit rule') : 'Automation rules'}
            </Dialog.Title>
            <Dialog.Close asChild>
              <button aria-label="Close" className="rounded-leo-sm p-1 text-text-secondary hover:bg-surface-elevated">
                <X className="h-4 w-4" />
              </button>
            </Dialog.Close>
          </div>

          {editing ? (
            <RuleEditor rule={editing === 'new' ? undefined : editing} onDone={() => setEditing(null)} />
          ) : (
            <div className="flex flex-col gap-3">
              <p className="text-xs text-text-secondary">
                Rules scan attendees, title, notes, and location. A rule matches if any of its condition groups match; its
                project tag is then added automatically — existing tags on the item are left alone.
              </p>

              {rules.length === 0 ? (
                <p className="text-sm text-text-secondary">No rules yet.</p>
              ) : (
                <ul className="flex flex-col gap-2">
                  {rules.map((rule) => (
                    <li key={rule.id} className="flex items-center gap-2 rounded-leo-md border border-divider p-2">
                      <Checkbox
                        checked={rule.enabled}
                        onCheckedChange={(checked) => void updateRule(rule.id, { enabled: checked === true })}
                        aria-label={rule.enabled ? `Disable "${rule.name}"` : `Enable "${rule.name}"`}
                      />
                      <div className="flex flex-1 items-center gap-2 overflow-hidden">
                        <div className="flex min-w-0 flex-col gap-0.5">
                          <span className="truncate text-sm font-medium text-text-primary">{rule.name}</span>
                          <span className="text-xs text-text-secondary">{ruleSummary(rule)}</span>
                        </div>
                        <span className="shrink-0 text-text-secondary">→</span>
                        <TagChip tag={{ id: rule.id, name: rule.targetProjectName, colorRaw: rule.targetProjectColor }} />
                      </div>
                      <button
                        type="button"
                        onClick={() => setEditing(rule)}
                        aria-label={`Edit "${rule.name}"`}
                        className="shrink-0 rounded-leo-sm p-1.5 text-text-secondary hover:bg-surface-elevated hover:text-text-primary"
                      >
                        <Pencil className="h-3.5 w-3.5" />
                      </button>
                      <button
                        type="button"
                        onClick={() => void deleteRule(rule.id)}
                        aria-label={`Delete "${rule.name}"`}
                        className="shrink-0 rounded-leo-sm p-1.5 text-text-secondary hover:bg-surface-elevated hover:text-danger"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </li>
                  ))}
                </ul>
              )}

              <div className="mt-1 flex items-center justify-between gap-2">
                <Button type="button" variant="outline" size="sm" onClick={() => setEditing('new')} className="gap-1.5">
                  <Plus className="h-3.5 w-3.5" aria-hidden="true" />
                  New rule
                </Button>
                <Button
                  type="button"
                  size="sm"
                  onClick={() => void handleRunNow()}
                  disabled={rules.filter((r) => r.enabled).length === 0 || running}
                  className="gap-1.5"
                >
                  <Play className="h-3.5 w-3.5" aria-hidden="true" />
                  {running ? 'Running…' : 'Run rules now'}
                </Button>
              </div>
            </div>
          )}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  )
}
