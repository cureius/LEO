/**
 * Real, current Anthropic model IDs — NOT a literal transliteration of the
 * Swift app's `ClaudeModels.swift` constants, which are one generation
 * behind (`claude-opus-4-7`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`
 * was current at the time that Swift code was written).
 */
export type ClaudeModel = 'claude-opus-4-8' | 'claude-sonnet-5' | 'claude-haiku-4-5-20251001'

export type ContentBlock =
  | { type: 'text'; text: string }
  | { type: 'tool_use'; id: string; name: string; input: unknown }
  | { type: 'tool_result'; tool_use_id: string; content: string; is_error?: boolean }
  /** PDF (or other supported document) attachment — Claude reads it natively
   *  (text, tables, layout, embedded images), no client-side text extraction. */
  | { type: 'document'; source: { type: 'base64'; media_type: string; data: string } }
  /** Photo attachment sent to Claude Vision — the on-device-OCR-failed fallback
   *  path (ocr.ts) when text extraction found nothing readable. Mirrors
   *  LEO/AI/Cloud/ClaudeModels.swift's ImageBlock. */
  | { type: 'image'; source: { type: 'base64'; media_type: string; data: string } }

export type Message = {
  role: 'user' | 'assistant'
  content: string | ContentBlock[]
}

export type SystemBlock = { type: 'text'; text: string; cache_control?: { type: 'ephemeral' } }

export type ToolDefinition = {
  name: string
  description: string
  input_schema: Record<string, unknown>
}

export type ClaudeUsage = {
  inputTokens: number
  outputTokens: number
  cacheCreationInputTokens?: number
  cacheReadInputTokens?: number
}

export type ClaudeResponse = {
  id: string
  model: string
  content: ContentBlock[]
  stopReason: string | null
  usage: ClaudeUsage
}

export type StreamEvent =
  | { type: 'messageStart'; id: string; model: string }
  | { type: 'contentBlockDelta'; index: number; text: string }
  | { type: 'toolUse'; id: string; name: string; inputJSON: string }
  | { type: 'messageStop'; stopReason: string; usage?: ClaudeUsage }
  | { type: 'error'; message: string }
