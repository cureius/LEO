import { describe, expect, it, vi, afterEach } from 'vitest'
import { send, stream, ClaudeError } from '../claudeClient'

function sseResponse(events: string[], status = 200): Response {
  const body = events.map((e) => `data: ${e}\n\n`).join('') + 'data: [DONE]\n\n'
  const encoder = new TextEncoder()
  const readable = new ReadableStream({
    start(controller) {
      controller.enqueue(encoder.encode(body))
      controller.close()
    },
  })
  return new Response(readable, { status })
}

async function collect<T>(gen: AsyncGenerator<T>): Promise<T[]> {
  const out: T[] = []
  for await (const item of gen) out.push(item)
  return out
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('stream() — SSE parsing, ported from ClaudeClient.swift', () => {
  it('parses message_start', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(sseResponse([JSON.stringify({ type: 'message_start', message: { id: 'msg_1', model: 'claude-opus-4-8' } })])),
    )
    const events = await collect(stream('key', 'claude-opus-4-8', []))
    expect(events[0]).toEqual({ type: 'messageStart', id: 'msg_1', model: 'claude-opus-4-8' })
  })

  it('parses plain-text content_block_delta events', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        sseResponse([
          JSON.stringify({ type: 'content_block_delta', index: 0, delta: { text: 'Hello' } }),
          JSON.stringify({ type: 'content_block_delta', index: 0, delta: { text: ' world' } }),
        ]),
      ),
    )
    const events = await collect(stream('key', 'claude-opus-4-8', []))
    expect(events).toEqual([
      { type: 'contentBlockDelta', index: 0, text: 'Hello' },
      { type: 'contentBlockDelta', index: 0, text: ' world' },
    ])
  })

  it('accumulates partial_json across multiple deltas and emits one toolUse on content_block_stop', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        sseResponse([
          JSON.stringify({ type: 'content_block_start', index: 0, content_block: { type: 'tool_use', id: 'tool_1', name: 'get_today' } }),
          JSON.stringify({ type: 'content_block_delta', index: 0, delta: { partial_json: '{"da' } }),
          JSON.stringify({ type: 'content_block_delta', index: 0, delta: { partial_json: 'te":"2026-' } }),
          JSON.stringify({ type: 'content_block_delta', index: 0, delta: { partial_json: '07-18"}' } }),
          JSON.stringify({ type: 'content_block_stop', index: 0 }),
        ]),
      ),
    )
    const events = await collect(stream('key', 'claude-opus-4-8', []))
    // content_block_start itself yields nothing (matches Swift — it only
    // records id/name for later), only content_block_stop flushes the event.
    expect(events).toEqual([{ type: 'toolUse', id: 'tool_1', name: 'get_today', inputJSON: '{"date":"2026-07-18"}' }])
  })

  it('a zero-argument tool call (no partial_json deltas at all, e.g. get_today\'s empty input_schema) still emits toolUse with "{}", not dropped', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        sseResponse([
          JSON.stringify({ type: 'content_block_start', index: 0, content_block: { type: 'tool_use', id: 'tool_1', name: 'get_today' } }),
          JSON.stringify({ type: 'content_block_stop', index: 0 }),
        ]),
      ),
    )
    const events = await collect(stream('key', 'claude-opus-4-8', []))
    expect(events).toEqual([{ type: 'toolUse', id: 'tool_1', name: 'get_today', inputJSON: '{}' }])
  })

  it('handles multiple interleaved tool_use blocks by index, not assuming a single active block', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        sseResponse([
          JSON.stringify({ type: 'content_block_start', index: 0, content_block: { type: 'tool_use', id: 'a', name: 'tool_a' } }),
          JSON.stringify({ type: 'content_block_start', index: 1, content_block: { type: 'tool_use', id: 'b', name: 'tool_b' } }),
          JSON.stringify({ type: 'content_block_delta', index: 1, delta: { partial_json: '{"b":1}' } }),
          JSON.stringify({ type: 'content_block_delta', index: 0, delta: { partial_json: '{"a":1}' } }),
          JSON.stringify({ type: 'content_block_stop', index: 1 }),
          JSON.stringify({ type: 'content_block_stop', index: 0 }),
        ]),
      ),
    )
    const events = await collect(stream('key', 'claude-opus-4-8', []))
    expect(events).toEqual([
      { type: 'toolUse', id: 'b', name: 'tool_b', inputJSON: '{"b":1}' },
      { type: 'toolUse', id: 'a', name: 'tool_a', inputJSON: '{"a":1}' },
    ])
  })

  it('parses message_delta with stop_reason and usage', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        sseResponse([
          JSON.stringify({ type: 'message_delta', delta: { stop_reason: 'end_turn' }, usage: { input_tokens: 10, output_tokens: 20 } }),
        ]),
      ),
    )
    const events = await collect(stream('key', 'claude-opus-4-8', []))
    expect(events).toEqual([
      { type: 'messageStop', stopReason: 'end_turn', usage: { inputTokens: 10, outputTokens: 20, cacheCreationInputTokens: undefined, cacheReadInputTokens: undefined } },
    ])
  })

  it('parses an error event', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(sseResponse([JSON.stringify({ type: 'error', error: { message: 'overloaded' } })])))
    const events = await collect(stream('key', 'claude-opus-4-8', []))
    expect(events).toEqual([{ type: 'error', message: 'overloaded' }])
  })

  it('stops at the [DONE] sentinel without yielding further events', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(sseResponse([])))
    const events = await collect(stream('key', 'claude-opus-4-8', []))
    expect(events).toEqual([])
  })

  it('handles an SSE chunk split mid-line across two stream reads', async () => {
    const encoder = new TextEncoder()
    const full = `data: ${JSON.stringify({ type: 'content_block_delta', index: 0, delta: { text: 'split' } })}\n\ndata: [DONE]\n\n`
    const splitPoint = 20 // deliberately mid-JSON
    const readable = new ReadableStream({
      start(controller) {
        controller.enqueue(encoder.encode(full.slice(0, splitPoint)))
        controller.enqueue(encoder.encode(full.slice(splitPoint)))
        controller.close()
      },
    })
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(readable, { status: 200 })))
    const events = await collect(stream('key', 'claude-opus-4-8', []))
    expect(events).toEqual([{ type: 'contentBlockDelta', index: 0, text: 'split' }])
  })

  it('throws ClaudeError with kind "unauthorized" on a 401', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('', { status: 401 })))
    await expect(collect(stream('key', 'claude-opus-4-8', []))).rejects.toMatchObject({ kind: 'unauthorized' })
  })

  it('throws ClaudeError with kind "missingAPIKey" when no key is provided, without ever calling fetch', async () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)
    await expect(collect(stream('', 'claude-opus-4-8', []))).rejects.toBeInstanceOf(ClaudeError)
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('aborts and throws a clear error if the request hangs with no response at all — regression for "stuck at … forever with a valid key, no error ever thrown"', async () => {
    vi.useFakeTimers()
    try {
      vi.stubGlobal(
        'fetch',
        vi.fn().mockImplementation((_url: string, init: RequestInit) => {
          // Never resolves on its own — only reacts to the abort signal, simulating
          // a connection that stalls before any response headers ever arrive.
          return new Promise((_resolve, reject) => {
            init.signal?.addEventListener('abort', () => {
              const err = new Error('The operation was aborted')
              err.name = 'AbortError'
              reject(err)
            })
          })
        }),
      )
      // Attach the rejection assertion synchronously, before advancing timers —
      // otherwise there's a gap where the promise rejects with nothing yet
      // listening, which Node flags as an unhandled rejection even though the
      // test itself still passes.
      const assertion = expect(collect(stream('key', 'claude-opus-4-8', []))).rejects.toThrow(/stalled/)
      await vi.advanceTimersByTimeAsync(75_000)
      await assertion
    } finally {
      vi.useRealTimers()
    }
  })

  it('does not time out a request that is merely slow to respond, as long as it arrives before the idle threshold — regression for the 30s timeout firing on legitimate multi-tool requests', async () => {
    vi.useFakeTimers()
    try {
      vi.stubGlobal(
        'fetch',
        vi.fn().mockImplementation(
          () =>
            new Promise((resolve) => {
              setTimeout(
                () => resolve(sseResponse([JSON.stringify({ type: 'message_delta', delta: { stop_reason: 'end_turn' } })])),
                70_000, // slow, but under the 75s idle threshold
              )
            }),
        ),
      )
      const resultPromise = collect(stream('key', 'claude-opus-4-8', []))
      await vi.advanceTimersByTimeAsync(70_000)
      const events = await resultPromise
      expect(events).toEqual([{ type: 'messageStop', stopReason: 'end_turn', usage: undefined }])
    } finally {
      vi.useRealTimers()
    }
  })
})

describe('send() — non-streaming API, must transform Anthropic\'s raw snake_case JSON into ClaudeResponse', () => {
  it('parses stop_reason and usage into camelCase — regression: `return response.json()` type-checked as ClaudeResponse while returning the raw snake_case body untouched, so .stopReason was always undefined on every real response', async () => {
    // This is the ACTUAL shape Anthropic's Messages API returns — snake_case
    // throughout, "content" is the only field name that happens to match the
    // camelCase type by coincidence, which is exactly why this bug was easy
    // to miss: content-only assertions would have passed regardless.
    const rawAnthropicResponse = {
      id: 'msg_01abc',
      type: 'message',
      role: 'assistant',
      model: 'claude-opus-4-8',
      content: [{ type: 'tool_use', id: 'toolu_1', name: 'get_today', input: {} }],
      stop_reason: 'tool_use',
      stop_sequence: null,
      usage: { input_tokens: 42, output_tokens: 7, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 },
    }
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify(rawAnthropicResponse), { status: 200 })))

    const result = await send('key', 'claude-opus-4-8', [])

    expect(result.stopReason).toBe('tool_use')
    expect(result.content).toEqual([{ type: 'tool_use', id: 'toolu_1', name: 'get_today', input: {} }])
    expect(result.usage).toEqual({
      inputTokens: 42,
      outputTokens: 7,
      cacheCreationInputTokens: 0,
      cacheReadInputTokens: 0,
    })
  })

  it('a response with stop_reason "end_turn" and only text content parses correctly too', async () => {
    const rawAnthropicResponse = {
      id: 'msg_02',
      model: 'claude-opus-4-8',
      content: [{ type: 'text', text: 'Hello!' }],
      stop_reason: 'end_turn',
      usage: { input_tokens: 5, output_tokens: 2 },
    }
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify(rawAnthropicResponse), { status: 200 })))

    const result = await send('key', 'claude-opus-4-8', [])
    expect(result.stopReason).toBe('end_turn')
    expect(result.content).toEqual([{ type: 'text', text: 'Hello!' }])
  })

  it('throws ClaudeError with kind "unauthorized" on a 401, same as stream()', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('', { status: 401 })))
    await expect(send('key', 'claude-opus-4-8', [])).rejects.toMatchObject({ kind: 'unauthorized' })
  })
})
