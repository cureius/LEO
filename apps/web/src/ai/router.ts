import type { ClaudeModel } from './models'

/** Port of AIRouter.swift's `Override` enum + UserDefaults-backed preference — localStorage here instead. */
export type RoutingOverride = 'none' | 'always_opus' | 'prefer_cheap'

const OVERRIDE_STORAGE_KEY = 'leo_ai_routing_override'

export function getRoutingOverride(): RoutingOverride {
  const raw = localStorage.getItem(OVERRIDE_STORAGE_KEY)
  if (raw === 'always_opus' || raw === 'prefer_cheap' || raw === 'none') return raw
  // No stored preference at all (fresh install, Settings never opened) —
  // defaults to cheap rather than 'none's auto-escalating heuristic, since
  // for personal/single-user use Haiku-only cost is negligible while Auto's
  // Sonnet/Opus escalation on any tool call adds up fast for no benefit most
  // users need. 'none' itself is still a real, explicit choice — picking
  // "Auto" in AISettingsPanel stores the literal string 'none' and is
  // respected above, this branch only ever fires when nothing was chosen.
  return 'prefer_cheap'
}

export function setRoutingOverride(override: RoutingOverride): void {
  localStorage.setItem(OVERRIDE_STORAGE_KEY, override)
}

/** Port of AIRouter.swift's routing heuristic, retargeted at the real current model IDs (see models.ts). */
export function route(prompt: string, expectedToolCalls = 0, userExplicitlyQuick = false): ClaudeModel {
  const override = getRoutingOverride()
  if (override === 'always_opus') return 'claude-opus-4-8'
  if (override === 'prefer_cheap') return 'claude-haiku-4-5-20251001'

  if (userExplicitlyQuick) return 'claude-haiku-4-5-20251001'
  if (expectedToolCalls >= 4 || prompt.length > 2000) return 'claude-opus-4-8'
  if (expectedToolCalls >= 1) return 'claude-sonnet-5'
  return 'claude-haiku-4-5-20251001'
}
