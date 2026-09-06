import { describe, expect, it, beforeEach } from 'vitest'
import { route, getRoutingOverride, setRoutingOverride } from '../router'

beforeEach(() => {
  localStorage.clear()
})

describe('route() — model selection heuristic', () => {
  // These tests exercise the "Auto" heuristic itself, which only runs under
  // override 'none' — the default is now 'prefer_cheap' (see the override
  // describe block below), which would short-circuit every one of these to
  // Haiku before the heuristic ever ran.
  beforeEach(() => {
    setRoutingOverride('none')
  })

  it('routes a long prompt (>2000 chars) to Opus', () => {
    const longPrompt = 'a'.repeat(2001)
    expect(route(longPrompt, 1)).toBe('claude-opus-4-8')
  })

  it('routes a short prompt with an expected tool call to Sonnet, not Opus', () => {
    // Regression: the only real call site once passed `String(promptLength)`
    // instead of the actual prompt text, so `prompt.length` checked the
    // digit-count of the length (e.g. "50".length === 2) instead of the
    // prompt's real length — the long-prompt-to-Opus branch was dead code
    // for every message regardless of actual length. A short prompt must
    // NOT route to Opus just because its length happens to stringify short.
    expect(route('short message', 1)).toBe('claude-sonnet-5')
  })

  it('routes 4+ expected tool calls to Opus even for a short prompt', () => {
    expect(route('short', 4)).toBe('claude-opus-4-8')
  })

  it('routes a prompt with no expected tool calls to Haiku', () => {
    expect(route('hi', 0)).toBe('claude-haiku-4-5-20251001')
  })

  it('userExplicitlyQuick forces Haiku regardless of prompt length or tool calls', () => {
    expect(route('a'.repeat(3000), 5, true)).toBe('claude-haiku-4-5-20251001')
  })
})

describe('routing override — port of AIRouter.swift\'s Override enum', () => {
  it('defaults to "prefer_cheap" when nothing is stored', () => {
    expect(getRoutingOverride()).toBe('prefer_cheap')
  })

  it('respects an explicit "none" (Auto) choice rather than falling back to the default', () => {
    setRoutingOverride('none')
    expect(getRoutingOverride()).toBe('none')
  })

  it('always_opus overrides even a trivial prompt with no tool calls', () => {
    setRoutingOverride('always_opus')
    expect(route('hi', 0)).toBe('claude-opus-4-8')
  })

  it('prefer_cheap overrides even a long prompt with many expected tool calls', () => {
    setRoutingOverride('prefer_cheap')
    expect(route('a'.repeat(3000), 5)).toBe('claude-haiku-4-5-20251001')
  })

  it('none falls through to the normal heuristic', () => {
    setRoutingOverride('none')
    expect(route('a'.repeat(2001), 1)).toBe('claude-opus-4-8')
  })
})
