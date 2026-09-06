import type { ClaudeModel, ClaudeUsage } from './models'

/**
 * Port of LEO/AI/Cloud/AITelemetry.swift — token usage + approximate USD cost
 * tracking, localStorage-persisted (native uses a JSON file in Documents;
 * same rotate-at-100 / this-month-rollup shape here).
 */
export type AIRequestRecord = {
  id: string
  timestamp: string // ISO8601
  model: ClaudeModel
  inputTokens: number
  outputTokens: number
  cacheCreationTokens: number
  cacheReadTokens: number
}

const STORAGE_KEY = 'leo_ai_telemetry'
const MAX_RECORDS = 100

/** Approximate pricing (USD per million tokens) — update before release. Matches AITelemetry.swift's table. */
function ratesFor(model: ClaudeModel): { inputMTok: number; outputMTok: number } {
  if (model === 'claude-opus-4-8') return { inputMTok: 15.0, outputMTok: 75.0 }
  if (model === 'claude-sonnet-5') return { inputMTok: 3.0, outputMTok: 15.0 }
  return { inputMTok: 0.8, outputMTok: 4.0 } // haiku
}

export function totalCostUSD(record: AIRequestRecord): number {
  const rates = ratesFor(record.model)
  return (record.inputTokens / 1_000_000) * rates.inputMTok + (record.outputTokens / 1_000_000) * rates.outputMTok
}

function load(): AIRequestRecord[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? parsed : []
  } catch {
    return []
  }
}

function persist(records: AIRequestRecord[]): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(records))
  } catch {
    // Storage full/unavailable — telemetry is a nice-to-have, never worth surfacing an error for.
  }
}

/**
 * Records one request's usage. Called after every `send()`/`stream()` call
 * that returns real usage — unlike the native app's original implementation,
 * which only recorded `send()` (the rare non-streaming fallback path) and
 * left the AI Usage screen effectively dead for real streamed conversations;
 * fixed on native alongside this port, both now record every call.
 */
export function recordUsage(model: ClaudeModel, usage: ClaudeUsage | undefined): void {
  const record: AIRequestRecord = {
    id: crypto.randomUUID(),
    timestamp: new Date().toISOString(),
    model,
    inputTokens: usage?.inputTokens ?? 0,
    outputTokens: usage?.outputTokens ?? 0,
    cacheCreationTokens: usage?.cacheCreationInputTokens ?? 0,
    cacheReadTokens: usage?.cacheReadInputTokens ?? 0,
  }
  const records = load()
  records.push(record)
  const rotated = records.length > MAX_RECORDS ? records.slice(records.length - MAX_RECORDS) : records
  persist(rotated)
}

export function allRecords(): AIRequestRecord[] {
  return load()
}

export function recordsThisMonth(): AIRequestRecord[] {
  const now = new Date()
  const start = new Date(now.getFullYear(), now.getMonth(), 1)
  return load().filter((r) => new Date(r.timestamp) >= start)
}

export function totalTokensThisMonth(): { input: number; output: number } {
  const monthly = recordsThisMonth()
  return {
    input: monthly.reduce((n, r) => n + r.inputTokens, 0),
    output: monthly.reduce((n, r) => n + r.outputTokens, 0),
  }
}
