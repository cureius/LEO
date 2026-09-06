import { describe, expect, it, beforeEach, vi } from 'vitest'
import { allRecords, recordUsage, recordsThisMonth, totalCostUSD, totalTokensThisMonth } from '../telemetry'

beforeEach(() => {
  localStorage.clear()
})

describe('telemetry — port of AITelemetry.swift', () => {
  it('recordUsage persists a record with the given model and token counts', () => {
    recordUsage('claude-sonnet-5', { inputTokens: 100, outputTokens: 50 })
    const records = allRecords()
    expect(records).toHaveLength(1)
    expect(records[0]).toMatchObject({ model: 'claude-sonnet-5', inputTokens: 100, outputTokens: 50 })
  })

  it('defaults missing usage fields to 0 rather than throwing', () => {
    recordUsage('claude-haiku-4-5-20251001', undefined)
    expect(allRecords()[0]).toMatchObject({ inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0 })
  })

  it('rotates at 100 records, keeping the most recent', () => {
    for (let i = 0; i < 105; i++) {
      recordUsage('claude-haiku-4-5-20251001', { inputTokens: i, outputTokens: 0 })
    }
    const records = allRecords()
    expect(records).toHaveLength(100)
    // The first 5 (inputTokens 0-4) should have been rotated out.
    expect(records[0].inputTokens).toBe(5)
    expect(records[records.length - 1].inputTokens).toBe(104)
  })

  it('totalTokensThisMonth sums only records from this month', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-07-15T12:00:00Z'))
    recordUsage('claude-sonnet-5', { inputTokens: 100, outputTokens: 10 })
    vi.setSystemTime(new Date('2026-06-15T12:00:00Z')) // last month
    recordUsage('claude-sonnet-5', { inputTokens: 999, outputTokens: 999 })
    vi.setSystemTime(new Date('2026-07-20T12:00:00Z'))

    const totals = totalTokensThisMonth()
    expect(totals).toEqual({ input: 100, output: 10 })
    expect(recordsThisMonth()).toHaveLength(1)
    vi.useRealTimers()
  })

  it('totalCostUSD computes per-model rates', () => {
    const record = { id: '1', timestamp: new Date().toISOString(), model: 'claude-opus-4-8' as const, inputTokens: 1_000_000, outputTokens: 1_000_000, cacheCreationTokens: 0, cacheReadTokens: 0 }
    // Opus: $15/MTok in, $75/MTok out -> $90 for 1M/1M.
    expect(totalCostUSD(record)).toBeCloseTo(90, 5)
  })
})
