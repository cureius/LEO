import { describe, expect, it, vi, beforeEach } from 'vitest'
import type { ClaudeResponse, Message, StreamEvent } from '../models'

let capturedCalls: Message[][] = []
let sendCalls: Message[][] = []
type StreamImpl = (apiKey: string, model: string, messages: Message[]) => AsyncGenerator<StreamEvent>
type SendImpl = (apiKey: string, model: string, messages: Message[]) => Promise<ClaudeResponse>

const defaultStreamImpl: StreamImpl = async function* (_apiKey, _model, messages) {
  capturedCalls.push(messages)
  yield { type: 'messageStop', stopReason: 'end_turn' }
}
const defaultSendImpl: SendImpl = () => {
  throw new Error('send() should not be called unless the streaming-tool_use fallback triggers')
}
let streamImpl: StreamImpl = defaultStreamImpl
let sendImpl: SendImpl = defaultSendImpl

type ExecuteToolImpl = (name: string, inputJSON: string) => Promise<{ result: string; isError: boolean }>
const defaultExecuteToolImpl: ExecuteToolImpl = async () => ({ result: '{}', isError: false })
let executeToolImpl: ExecuteToolImpl = defaultExecuteToolImpl

type RecognizeTextImpl = (base64: string, mimeType: string) => Promise<string | null>
const defaultRecognizeTextImpl: RecognizeTextImpl = async () => null
let recognizeTextImpl: RecognizeTextImpl = defaultRecognizeTextImpl

vi.mock('../claudeClient', () => ({
  stream: vi.fn((apiKey: string, model: string, messages: Message[]) => streamImpl(apiKey, model, messages)),
  send: vi.fn((apiKey: string, model: string, messages: Message[]) => {
    sendCalls.push(messages)
    return sendImpl(apiKey, model, messages)
  }),
}))
vi.mock('../toolRuntime', () => ({
  executeTool: vi.fn((name: string, inputJSON: string) => executeToolImpl(name, inputJSON)),
  toolDefinitions: () => [],
}))
// Real tesseract.js spins up a Web Worker + WASM — not something to exercise
// in a unit test; mocked here the same way claudeClient/toolRuntime are, so
// sendUserMessage's OCR-branching logic (success vs fallback-to-image) can be
// tested deterministically.
vi.mock('../ocr', () => ({
  recognizeText: vi.fn((base64: string, mimeType: string) => recognizeTextImpl(base64, mimeType)),
}))

const { useChatStore, storeApiKey } = await import('../session/chatStore')
const { sendUserMessage } = await import('../chatOrchestrator')

beforeEach(() => {
  capturedCalls = []
  sendCalls = []
  streamImpl = defaultStreamImpl
  sendImpl = defaultSendImpl
  executeToolImpl = defaultExecuteToolImpl
  recognizeTextImpl = defaultRecognizeTextImpl
  storeApiKey('test-key')
  useChatStore.setState({ conversations: [], activeConversationId: null })
})

describe('sendUserMessage — regression: claudeMessages must reflect live state, not a stale getState() snapshot', () => {
  it('the first message of a brand-new conversation is sent as a real user turn, not an empty array', async () => {
    // Bug: chatOrchestrator captured `const store = useChatStore.getState()`
    // once, then read `store.messages` (now getActiveMessages()) AFTER two
    // store.addMessage() calls that mutate the real store — the local
    // snapshot never reflected them, so on a brand-new conversation this
    // array was `[]`, sending Claude a request with no messages at all.
    await sendUserMessage('What is on my schedule today?')
    expect(capturedCalls).toHaveLength(1)
    expect(capturedCalls[0]).toEqual([{ role: 'user', content: 'What is on my schedule today?' }])
  })

  it('the second message includes the full prior history plus the new message as the final turn', async () => {
    await sendUserMessage('First message')
    await sendUserMessage('Second message')
    expect(capturedCalls).toHaveLength(2)

    const secondCallMessages = capturedCalls[1]
    // The stale-snapshot bug this regresses against would end this array with
    // the ASSISTANT's turn from message 1, silently dropping message 2 —
    // Claude would respond to nothing new, or continue its own prior reply.
    expect(secondCallMessages[secondCallMessages.length - 1]).toEqual({ role: 'user', content: 'Second message' })
    expect(secondCallMessages.some((m) => m.role === 'user' && m.content === 'First message')).toBe(true)
  })
})

describe('sendUserMessage — regression: a "successful" turn must never leave the assistant message stuck empty forever', () => {
  it('a turn that resolves with stop_reason "end_turn" and zero text sets a visible error, not a silently-empty message', async () => {
    // Reported live: "stuck at … forever with a valid API key" — no exception
    // was ever thrown (nothing for the existing try/catch to catch), the
    // request just resolved successfully with nothing in it.
    await sendUserMessage('Say nothing')
    const last = useChatStore.getState().getActiveMessages().at(-1)!
    expect(last.text).toBe('')
    expect(last.error).toMatch(/empty response/i)
    // The diagnostic suffix is what turns the next live report of this into
    // an actual diagnosis instead of more blind guessing — lock in that it's
    // actually attached, not just the headline message.
    expect(last.error).toMatch(/sawEvents=true, stopReason=end_turn, toolCalls=0, textLen=0/)
  })

  it('a turn cut off by stop_reason "max_tokens" with nothing captured gets a distinct, actionable error — not the generic diagnostic dump', async () => {
    // Reported live: cut off mid-generation (most likely partway through a
    // large propose_cancel tool_use block) before content_block_stop ever
    // fired, so nothing usable was captured despite no exception being
    // thrown. This has an actual fix (ask for less at once), so it gets its
    // own message rather than the generic "empty response" diagnostic dump.
    streamImpl = async function* (_apiKey, _model, messages) {
      capturedCalls.push(messages)
      yield { type: 'messageStop', stopReason: 'max_tokens' }
    }
    await sendUserMessage('remove all my unfinished workout and meal items')
    const last = useChatStore.getState().getActiveMessages().at(-1)!
    expect(last.text).toBe('')
    expect(last.error).toMatch(/ran out of room/i)
    expect(last.error).not.toMatch(/diagnostic/i)
  })

  it('exhausting every tool-loop turn without ever reaching a final answer sets a visible error, not silence', async () => {
    streamImpl = async function* (_apiKey, _model, messages) {
      capturedCalls.push(messages)
      yield { type: 'toolUse', id: 't1', name: 'get_today', inputJSON: '{}' }
      yield { type: 'messageStop', stopReason: 'tool_use' }
    }
    await sendUserMessage('Keep calling tools forever')
    const last = useChatStore.getState().getActiveMessages().at(-1)!
    expect(last.error).toMatch(/kept calling tools/i)
    // 5 turns = MAX_TOOL_LOOP_TURNS
    expect(capturedCalls).toHaveLength(5)
  })
})

describe('sendUserMessage — regression: stop_reason "tool_use" with zero captured tool calls falls back to the non-streaming API', () => {
  it('reported live: streaming can report stop_reason "tool_use" while never yielding a toolUse event — retries via send() for that turn, then continues the loop normally with the recovered tool result', async () => {
    let streamCallCount = 0
    streamImpl = async function* (_apiKey, _model, messages) {
      capturedCalls.push(messages)
      streamCallCount++
      if (streamCallCount === 1) {
        // Turn 1 — the exact broken state seen live: message_delta parsed
        // fine (stop_reason present) but content_block_start/_stop never
        // produced a toolUse event.
        yield { type: 'messageStop', stopReason: 'tool_use' }
      } else {
        // Turn 2 — streaming recovers (or the bug was transient) and Claude
        // answers normally using the tool result the fallback obtained.
        yield { type: 'contentBlockDelta', index: 0, text: 'You have 2 events tomorrow.' }
        yield { type: 'messageStop', stopReason: 'end_turn' }
      }
    }
    sendImpl = async () => ({
      id: 'msg_1',
      model: 'claude-opus-4-8',
      stopReason: 'tool_use', // realistic: any message containing tool_use content has this stop_reason
      usage: { inputTokens: 1, outputTokens: 1 },
      content: [{ type: 'tool_use', id: 'tool_1', name: 'get_today', input: {} }],
    })

    await sendUserMessage('what events do I have tomorrow')

    expect(sendCalls).toHaveLength(1) // fell back exactly once for the broken turn, not every turn
    expect(streamCallCount).toBe(2) // turn 1 (broken, recovered) + turn 2 (normal answer)
    const last = useChatStore.getState().getActiveMessages().at(-1)!
    expect(last.error).toBeUndefined() // recovered — no visible error
    expect(last.text).toBe('You have 2 events tomorrow.')
  })

  it('does NOT fall back when toolUses were actually captured (only triggers on the specific empty-capture bug)', async () => {
    streamImpl = async function* (_apiKey, _model, messages) {
      capturedCalls.push(messages)
      yield { type: 'toolUse', id: 't1', name: 'get_today', inputJSON: '{}' }
      yield { type: 'messageStop', stopReason: 'end_turn' }
    }
    await sendUserMessage('a normal tool call that works fine')
    expect(sendCalls).toHaveLength(0)
  })
})

describe('sendUserMessage — regression: diff capture must not depend on the tool being named "propose_*"', () => {
  it('a DiffPayload returned by a tool NOT named "propose_*" (e.g. set_workout_exercises) still reaches pendingDiff', async () => {
    // Bug: runToolCalls only captured a diff when `toolUse.name.startsWith('propose_')`
    // — adjust_plan and set_workout_exercises both return real DiffPayloads
    // but neither name matches that prefix, so their diffs silently vanished:
    // DiffReview never rendered, applyDiffChanges never ran, and the model
    // had no way to know its "successful" tool_result (isError: false) had
    // actually accomplished nothing.
    const payload = {
      changes: [{ itemID: 'w1', kind: 'update', field: 'workoutDetail', newValue: '{"exercises":[]}' }],
      rationale: 'Filling in exercises from the attached PDF',
    }
    let streamCallCount = 0
    streamImpl = async function* (_apiKey, _model, messages) {
      capturedCalls.push(messages)
      streamCallCount++
      if (streamCallCount === 1) {
        yield { type: 'toolUse', id: 't1', name: 'set_workout_exercises', inputJSON: '{}' }
        yield { type: 'messageStop', stopReason: 'tool_use' }
      } else {
        yield { type: 'contentBlockDelta', index: 0, text: 'Updated.' }
        yield { type: 'messageStop', stopReason: 'end_turn' }
      }
    }
    executeToolImpl = async (name) =>
      name === 'set_workout_exercises' ? { result: JSON.stringify(payload), isError: false } : { result: '{}', isError: false }

    await sendUserMessage('fill in the exercises for workout day 1')

    const last = useChatStore.getState().getActiveMessages().at(-1)!
    expect(last.pendingDiff).toEqual(payload)
  })
})

describe('sendUserMessage — activeTool: the "Checking today\'s schedule…" indicator', () => {
  it('sets activeTool to the tool name while a tool call is executing, and clears it once text starts streaming', async () => {
    let activeToolDuringExecution: string | undefined
    executeToolImpl = async () => {
      // Captured synchronously — onToolStart() already ran in the same tick,
      // before executeTool's own (mocked) async work "completes".
      activeToolDuringExecution = useChatStore.getState().getActiveMessages().at(-1)?.activeTool
      return { result: '{}', isError: false }
    }
    let streamCallCount = 0
    streamImpl = async function* (_apiKey, _model, messages) {
      capturedCalls.push(messages)
      streamCallCount++
      if (streamCallCount === 1) {
        yield { type: 'toolUse', id: 't1', name: 'get_week', inputJSON: '{}' }
        yield { type: 'messageStop', stopReason: 'tool_use' }
      } else {
        yield { type: 'contentBlockDelta', index: 0, text: 'Done.' }
        yield { type: 'messageStop', stopReason: 'end_turn' }
      }
    }

    await sendUserMessage('what do I have this week')

    expect(activeToolDuringExecution).toBe('get_week')
    // Cleared once the final answer streamed in — a stale "Checking your
    // schedule…" must never linger under a completed response.
    const last = useChatStore.getState().getActiveMessages().at(-1)!
    expect(last.activeTool).toBeUndefined()
    expect(last.text).toBe('Done.')
  })

  it('clears a previously-set activeTool when a later turn fails, so an error message never shows a stale tool label', async () => {
    let turnCount = 0
    streamImpl = async function* (_apiKey, _model, messages) {
      capturedCalls.push(messages)
      turnCount++
      if (turnCount === 1) {
        // Turn 1 succeeds and sets activeTool via a real tool call.
        yield { type: 'toolUse', id: 't1', name: 'get_today', inputJSON: '{}' }
        yield { type: 'messageStop', stopReason: 'tool_use' }
      } else {
        // Turn 2 fails outright — activeTool from turn 1 must not linger.
        yield { type: 'error', message: 'boom' }
      }
    }
    await expect(sendUserMessage('trigger a failure after a tool call')).rejects.toThrow()
    const last = useChatStore.getState().getActiveMessages().at(-1)!
    expect(last.activeTool).toBeUndefined()
    expect(last.error).toBe('boom')
  })
})

describe('sendUserMessage — PDF attachments', () => {
  it('sends a document content block ahead of the text block when an attachment is present', async () => {
    await sendUserMessage('what does this say?', [{ name: 'invoice.pdf', mimeType: 'application/pdf', base64: 'ZmFrZQ==', sizeBytes: 4, kind: 'pdf' as const }])

    expect(capturedCalls).toHaveLength(1)
    const content = capturedCalls[0][0].content
    expect(content).toEqual([
      { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: 'ZmFrZQ==' } },
      { type: 'text', text: 'what does this say?' },
    ])
  })

  it('sends only the document block when the message has no text (attachment-only message)', async () => {
    await sendUserMessage('', [{ name: 'invoice.pdf', mimeType: 'application/pdf', base64: 'ZmFrZQ==', sizeBytes: 4, kind: 'pdf' as const }])
    const content = capturedCalls[0][0].content
    expect(content).toEqual([{ type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: 'ZmFrZQ==' } }])
  })

  it('a plain message with no attachments still sends plain string content, not an array', async () => {
    await sendUserMessage('no attachment here')
    expect(capturedCalls[0][0].content).toBe('no attachment here')
  })

  it('persists the attachment onto the stored user message so it survives to re-render', async () => {
    await sendUserMessage('check this', [{ name: 'invoice.pdf', mimeType: 'application/pdf', base64: 'ZmFrZQ==', sizeBytes: 4, kind: 'pdf' as const }])
    const userMessage = useChatStore.getState().getActiveMessages()[0]
    expect(userMessage.attachments).toHaveLength(1)
    expect(userMessage.attachments![0]).toMatchObject({ name: 'invoice.pdf', mimeType: 'application/pdf', sizeBytes: 4 })
  })

  it('a follow-up question in the SAME session still resends the earlier attachment\'s bytes, so multi-turn Q&A about a PDF works', async () => {
    await sendUserMessage('summarize this', [{ name: 'invoice.pdf', mimeType: 'application/pdf', base64: 'ZmFrZQ==', sizeBytes: 4, kind: 'pdf' as const }])
    await sendUserMessage('what is the total?')

    expect(capturedCalls).toHaveLength(2)
    const secondCallMessages = capturedCalls[1]
    // The first turn's message (with the document block) must still be present.
    expect(secondCallMessages[0].content).toEqual([
      { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: 'ZmFrZQ==' } },
      { type: 'text', text: 'summarize this' },
    ])
  })
})

describe('sendUserMessage — photo attachments (hybrid on-device OCR, mirrors VisionOCRService.swift)', () => {
  const photo = { name: 'notes.jpg', mimeType: 'image/jpeg', base64: 'ZmFrZS1qcGVn', sizeBytes: 4, kind: 'image' as const }

  it('OCR success: sends only the extracted text, never the image bytes', async () => {
    recognizeTextImpl = async () => 'Buy milk\nCall dentist'
    await sendUserMessage('create tasks from this', [photo])

    const content = capturedCalls[0][0].content
    expect(content).toEqual([
      {
        type: 'text',
        text: 'I photographed some handwritten notes. Here is the text extracted on-device:\n\n---\nBuy milk\nCall dentist\n---\n\ncreate tasks from this',
      },
    ])
    // No image block anywhere in what was sent.
    expect(JSON.stringify(content)).not.toContain('"type":"image"')
  })

  it('OCR success: the stored message keeps the short original text, not the wrapped prompt (display vs API content differ)', async () => {
    recognizeTextImpl = async () => 'Buy milk'
    await sendUserMessage('create tasks from this', [photo])
    const stored = useChatStore.getState().getActiveMessages()[0]
    expect(stored.text).toBe('create tasks from this')
    expect(stored.ocrText).toBe('Buy milk')
    expect(stored.ocrSucceeded).toBe(true)
    expect(stored.attachments).toBeUndefined() // image bytes never persisted as an attachment on the success path
  })

  it('OCR failure (returns null): falls back to sending the actual image to Claude Vision', async () => {
    recognizeTextImpl = async () => null
    await sendUserMessage('what does this say?', [photo])

    const content = capturedCalls[0][0].content
    expect(content).toEqual([
      { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: 'ZmFrZS1qcGVn' } },
      { type: 'text', text: 'what does this say?' },
    ])
    const stored = useChatStore.getState().getActiveMessages()[0]
    expect(stored.ocrSucceeded).toBe(false)
    expect(stored.attachments).toHaveLength(1)
  })

  it('a PDF and a photo attached together: PDF skips OCR entirely, photo goes through it', async () => {
    recognizeTextImpl = async () => 'extracted text'
    const pdf = { name: 'doc.pdf', mimeType: 'application/pdf', base64: 'cGRmZGF0YQ==', sizeBytes: 4, kind: 'pdf' as const }
    await sendUserMessage('look at both', [pdf, photo])

    const content = capturedCalls[0][0].content
    // PDF still goes through as a real document block; the photo contributes
    // only its extracted text (no image block at all).
    expect(content).toEqual([
      { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: 'cGRmZGF0YQ==' } },
      {
        type: 'text',
        text: 'I photographed some handwritten notes. Here is the text extracted on-device:\n\n---\nextracted text\n---\n\nlook at both',
      },
    ])
  })
})
