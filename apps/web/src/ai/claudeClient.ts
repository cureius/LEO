import type { ClaudeModel, ClaudeResponse, ClaudeUsage, ContentBlock, Message, StreamEvent, SystemBlock, ToolDefinition } from './models'
import { recordUsage } from './telemetry'

/**
 * Port of LEO/AI/Cloud/ClaudeClient.swift. The Swift client calls
 * api.anthropic.com directly (fine for a native app — no CORS). A browser
 * can't do that without Anthropic's `anthropic-dangerous-direct-browser-access`
 * opt-in; instead this goes through `/api/claude`, a same-origin Vercel Edge
 * Function that does nothing but forward the request (see api/claude.ts).
 * Neither path hides the key from the user who owns it — see that file's
 * doc comment for what the proxy actually buys.
 */
const PROXY_URL = '/api/claude'
const ANTHROPIC_VERSION = '2023-06-01'
const ANTHROPIC_BETA = 'prompt-caching-2024-07-31'
// Was 4096 — raised after a real report of stop_reason "max_tokens" with
// ZERO captured text or tool calls: the model got cut off mid-generation
// (most likely partway through a tool_use block's JSON — e.g. propose_cancel
// with a long `ids` array) before content_block_stop ever fired, so nothing
// it had generated so far was usable. 4096 is tight for a response that also
// has to hold a non-trivial tool_use payload; 8192 gives real headroom
// without being unbounded.
const DEFAULT_MAX_TOKENS = 8192

export type ClaudeErrorKind = 'missingAPIKey' | 'unauthorized' | 'rateLimited' | 'serverError'

export class ClaudeError extends Error {
  readonly kind: ClaudeErrorKind
  constructor(message: string, kind: ClaudeErrorKind = 'serverError') {
    super(message)
    this.kind = kind
  }
}

function buildRequestBody(
  model: ClaudeModel,
  messages: Message[],
  tools: ToolDefinition[] | undefined,
  system: SystemBlock[] | undefined,
  maxTokens: number,
  stream: boolean,
) {
  const body: Record<string, unknown> = { model, max_tokens: maxTokens, messages }
  if (stream) body.stream = true
  if (system && system.length > 0) body.system = system
  if (tools && tools.length > 0) body.tools = tools
  return body
}

async function checkStatus(response: Response): Promise<void> {
  if (response.ok) return
  if (response.status === 401) throw new ClaudeError('Invalid API key', 'unauthorized')
  if (response.status === 429) throw new ClaudeError('Rate limited — try again shortly', 'rateLimited')
  const text = await response.text().catch(() => '')
  throw new ClaudeError(`Anthropic API error ${response.status}: ${text}`, 'serverError')
}

export async function send(
  apiKey: string,
  model: ClaudeModel,
  messages: Message[],
  options: { tools?: ToolDefinition[]; system?: SystemBlock[]; maxTokens?: number } = {},
): Promise<ClaudeResponse> {
  if (!apiKey) throw new ClaudeError('No API key set', 'missingAPIKey')
  const response = await fetch(PROXY_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-api-key': apiKey, 'anthropic-version': ANTHROPIC_VERSION, 'anthropic-beta': ANTHROPIC_BETA },
    body: JSON.stringify(buildRequestBody(model, messages, options.tools, options.system, options.maxTokens ?? DEFAULT_MAX_TOKENS, false)),
  })
  await checkStatus(response)

  // Anthropic's raw JSON is snake_case (stop_reason, input_tokens, ...) — the
  // `ClaudeResponse` type declares camelCase, but `response.json()` returns
  // `any`, so `return response.json()` type-checked fine while being a
  // complete lie at runtime: `.stopReason` was always `undefined` on every
  // real response. Confirmed live: this silently broke the tool_use fallback
  // in chatOrchestrator.ts, which read `response.stopReason ?? 'end_turn'`
  // and got 'end_turn' back 100% of the time regardless of what Claude
  // actually returned, discarding real tool results as if the turn had
  // already finished.
  const json = (await response.json()) as {
    id: string
    model: string
    content: ContentBlock[]
    stop_reason: string | null
    usage?: Record<string, unknown>
  }
  const result: ClaudeResponse = {
    id: json.id,
    model: json.model,
    content: json.content,
    stopReason: json.stop_reason,
    usage: parseUsage(json.usage) ?? { inputTokens: 0, outputTokens: 0 },
  }
  recordUsage(model, result.usage)
  return result
}

// No bytes at all — not even a keepalive — for this long means the
// connection has stalled. Without a bound on this, a hung fetch/reader left
// `sendUserMessage` awaiting forever: `sending` stays true (input disabled)
// and the assistant placeholder sits at "…" with no way to recover short of
// reloading the page. Caught live: reported as "stuck on … with a real,
// valid API key" — no exception was ever thrown for the try/catch further up
// the call chain to catch, because nothing had failed yet, it just never
// finished.
//
// Originally 30s, raised to 75s after a real report of this timeout firing
// on a legitimate (if slow) request — a multi-tool query (read a tool result,
// decide on a propose_cancel call) with a non-trivial system prompt is a
// genuinely slower case than a plain one-line reply, and 30s turned out to
// be short enough to routinely kill it before Claude produced a first token,
// not just to catch a truly hung connection. 75s trades a longer worst-case
// wait for not cutting off requests that would have succeeded.
const IDLE_TIMEOUT_MS = 75_000

/**
 * SSE streaming — a direct port of ClaudeClient.stream()'s state machine
 * using fetch()'s ReadableStream + TextDecoder, no SSE library needed. Same
 * two pieces of accumulation state as the Swift original: content_block_start
 * remembers each tool_use block's id/name by index, content_block_delta's
 * partial_json accumulates into a buffer keyed by the same index, and
 * content_block_stop flushes the accumulated JSON as one toolUse event.
 */
export async function* stream(
  apiKey: string,
  model: ClaudeModel,
  messages: Message[],
  options: { tools?: ToolDefinition[]; system?: SystemBlock[]; maxTokens?: number } = {},
): AsyncGenerator<StreamEvent> {
  if (!apiKey) throw new ClaudeError('No API key set', 'missingAPIKey')

  const controller = new AbortController()
  let timedOut = false
  const armIdleTimer = () =>
    setTimeout(() => {
      timedOut = true
      controller.abort()
    }, IDLE_TIMEOUT_MS)

  let response: Response
  let idleTimer = armIdleTimer()
  try {
    response = await fetch(PROXY_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': ANTHROPIC_VERSION,
        'anthropic-beta': ANTHROPIC_BETA,
        Accept: 'text/event-stream',
      },
      body: JSON.stringify(buildRequestBody(model, messages, options.tools, options.system, options.maxTokens ?? DEFAULT_MAX_TOKENS, true)),
      signal: controller.signal,
    })
  } catch (err) {
    if (timedOut) throw new ClaudeError(`No response from Claude within ${IDLE_TIMEOUT_MS / 1000}s — the request may have stalled. Try again.`, 'serverError')
    throw err
  } finally {
    clearTimeout(idleTimer)
  }

  await checkStatus(response)
  if (!response.body) throw new ClaudeError('No response body', 'serverError')

  const reader = response.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''
  const toolInputBuffer = new Map<number, string>()
  const toolBlockMeta = new Map<number, { id: string; name: string }>()

  while (true) {
    idleTimer = armIdleTimer()
    let readResult: ReadableStreamReadResult<Uint8Array>
    try {
      readResult = await reader.read()
    } catch (err) {
      if (timedOut) throw new ClaudeError(`No data from Claude for ${IDLE_TIMEOUT_MS / 1000}s — the connection may have stalled. Try again.`, 'serverError')
      throw err
    } finally {
      clearTimeout(idleTimer)
    }
    const { done, value } = readResult
    if (done) break
    buffer += decoder.decode(value, { stream: true })
    const lines = buffer.split('\n')
    buffer = lines.pop() ?? ''

    for (const line of lines) {
      if (!line.startsWith('data: ')) continue
      const payload = line.slice(6)
      if (payload === '[DONE]') return
      let json: Record<string, unknown>
      try {
        json = JSON.parse(payload)
      } catch {
        continue
      }

      // Raw, unfiltered log of every parsed SSE payload — deliberately BEFORE
      // the switch below, not just what gets yielded. content_block_start
      // never yields a StreamEvent at all (it only updates internal Maps),
      // so the orchestrator-level event logging added earlier couldn't see
      // it. Caught live: stopReason came back "tool_use" (proving
      // message_delta parses fine) while toolCalls stayed 0 — the only two
      // places that populate a tool call are content_block_start/_stop
      // below, so this is the direct way to see exactly what shape Claude
      // is actually sending for that block instead of guessing further.
      console.debug('[ask-leo raw SSE]', json.type, json)

      switch (json.type) {
        case 'message_start': {
          const message = json.message as { id?: string; model?: string } | undefined
          yield { type: 'messageStart', id: message?.id ?? '', model: message?.model ?? '' }
          break
        }
        case 'content_block_start': {
          const block = json.content_block as { type?: string; id?: string; name?: string } | undefined
          const index = (json.index as number) ?? 0
          if (block?.type === 'tool_use') {
            toolBlockMeta.set(index, { id: block.id ?? '', name: block.name ?? '' })
          }
          break
        }
        case 'content_block_delta': {
          const delta = json.delta as { text?: string; partial_json?: string } | undefined
          const index = (json.index as number) ?? 0
          if (typeof delta?.text === 'string') {
            yield { type: 'contentBlockDelta', index, text: delta.text }
          } else if (typeof delta?.partial_json === 'string') {
            toolInputBuffer.set(index, (toolInputBuffer.get(index) ?? '') + delta.partial_json)
          }
          break
        }
        case 'content_block_stop': {
          const index = (json.index as number) ?? 0
          const meta = toolBlockMeta.get(index)
          if (meta) {
            // A zero-argument tool call (empty input_schema.properties, e.g.
            // get_today) can close with no partial_json deltas at all — default
            // to '{}' rather than dropping the call, which would desync this
            // client's view of the conversation from what Claude actually did
            // (a tool_use block it remembers but we never report back), risking
            // a 400 on the next turn from mismatched tool_use/tool_result pairs.
            const inputJSON = toolInputBuffer.get(index) ?? '{}'
            yield { type: 'toolUse', id: meta.id, name: meta.name, inputJSON }
            toolInputBuffer.delete(index)
            toolBlockMeta.delete(index)
          }
          break
        }
        case 'message_delta': {
          const delta = json.delta as { stop_reason?: string } | undefined
          const usage = parseUsage(json.usage as Record<string, unknown> | undefined)
          recordUsage(model, usage)
          yield { type: 'messageStop', stopReason: delta?.stop_reason ?? '', usage }
          break
        }
        case 'error': {
          const error = json.error as { message?: string } | undefined
          yield { type: 'error', message: error?.message ?? 'Unknown error' }
          break
        }
      }
    }
  }
}

function parseUsage(json: Record<string, unknown> | undefined): ClaudeUsage | undefined {
  if (!json) return undefined
  return {
    inputTokens: (json.input_tokens as number) ?? 0,
    outputTokens: (json.output_tokens as number) ?? 0,
    cacheCreationInputTokens: json.cache_creation_input_tokens as number | undefined,
    cacheReadInputTokens: json.cache_read_input_tokens as number | undefined,
  }
}
