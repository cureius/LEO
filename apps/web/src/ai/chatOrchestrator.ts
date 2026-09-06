import { send, stream } from './claudeClient'
import { executeTool, toolDefinitions } from './toolRuntime'
import { route } from './router'
import { buildSystemPrompt, dynamicContextBlock } from './systemPrompt'
import { recognizeText } from './ocr'
import { useChatStore, loadStoredApiKey, type ChatAttachment, type ChatMessage } from './session/chatStore'
import type { ContentBlock, Message, SystemBlock } from './models'
import type { DiffPayload } from './diff/types'
import { getProvider } from './provider'
import { stream as webllmStream } from './webllm/webllmClient'
import type { ChatCompletionMessageParam } from '@mlc-ai/web-llm'

export type PendingAttachment = { name: string; mimeType: string; base64: string; sizeBytes: number; kind: 'pdf' | 'image' }

/** Builds what actually gets sent to Claude for one stored message — plain
 *  text normally, or a document/image-block-then-text array when attachments
 *  with live bytes are present, or (photo OCR succeeded) the extracted text
 *  woven into the prompt with no image bytes sent at all. A rehydrated-from-
 *  localStorage message whose attachment bytes were stripped on persist (see
 *  chatStore.ts's `partialize`) falls back to plain text for the image-
 *  attached case — the photo itself is gone, but the fact it was once
 *  attached and what was said about it are not; for the OCR-succeeded case,
 *  `ocrSucceeded`/`ocrText` themselves DO survive persistence (small text,
 *  unlike raw bytes), so a reload can still reconstruct the extracted-text
 *  prompt correctly. */
function buildMessageContent(message: ChatMessage): string | ContentBlock[] {
  const withBytes = message.attachments?.filter((a) => a.base64) ?? []
  const hasOCRText = message.ocrSucceeded && !!message.ocrText

  if (withBytes.length === 0 && !hasOCRText) return message.text

  const blocks: ContentBlock[] = withBytes.map((a) => ({
    type: a.kind === 'image' ? ('image' as const) : ('document' as const),
    source: { type: 'base64', media_type: a.mimeType, data: a.base64! },
  }))
  const text = hasOCRText
    ? `I photographed some handwritten notes. Here is the text extracted on-device:\n\n---\n${message.ocrText}\n---\n\n${message.text}`
    : message.text
  if (text) blocks.push({ type: 'text', text })
  return blocks
}

/**
 * Structural check, not a name-prefix check. This used to gate on
 * `toolUse.name.startsWith('propose_')`, which silently missed every propose
 * tool that isn't named that way — confirmed live: `adjust_plan` and
 * `set_workout_exercises` both return real DiffPayloads but neither name
 * starts with "propose_", so their diffs never reached DiffReview and
 * nothing they "applied" ever actually wrote anything. The model would then
 * report success (the tool_result came back with isError: false) with no
 * way to know the diff silently vanished. Checking the actual returned
 * shape instead of the tool's name is correct regardless of what any tool
 * happens to be called, present or future.
 */
function isDiffPayload(value: unknown): value is DiffPayload {
  return (
    typeof value === 'object' &&
    value !== null &&
    Array.isArray((value as { changes?: unknown }).changes) &&
    typeof (value as { rationale?: unknown }).rationale === 'string'
  )
}

/** Executes every tool_use block against the live registry and builds the
 *  tool_result/diff outputs — shared by both the streaming path and the
 *  non-streaming fallback below, since both end up with the same shape of
 *  "here are the tool_use blocks the model produced this turn." */
async function runToolCalls(
  toolUses: { id: string; name: string; input: unknown }[],
  onToolStart: (toolName: string) => void,
): Promise<{ toolResults: ContentBlock[]; diff: DiffPayload | null }> {
  const toolResults: ContentBlock[] = []
  let diff: DiffPayload | null = null
  for (const toolUse of toolUses) {
    onToolStart(toolUse.name)
    const { result, isError } = await executeTool(toolUse.name, JSON.stringify(toolUse.input))
    toolResults.push({ type: 'tool_result', tool_use_id: toolUse.id, content: result, is_error: isError })
    if (!diff && !isError) {
      try {
        const parsed = JSON.parse(result)
        if (isDiffPayload(parsed)) diff = parsed
      } catch {
        // Tool result wasn't JSON at all — leave diff unset.
      }
    }
  }
  return { toolResults, diff }
}

type TurnResult = {
  contentBlocks: ContentBlock[]
  toolResults: ContentBlock[]
  stopReason: string
  diff: DiffPayload | null
  /** Diagnostics for the "empty response" fallback message — see sendUserMessage. */
  sawAnyEvent: boolean
  textLength: number
  toolCallCount: number
}

async function runOneAssistantTurn(
  apiKey: string,
  claudeMessages: Message[],
  onTextDelta: (deltaText: string) => void,
  onToolStart: (toolName: string) => void,
): Promise<TurnResult> {
  const lastUserText = [...claudeMessages].reverse().find((m) => m.role === 'user')
  // route() checks prompt.length itself — passing the raw text, not its
  // stringified length (a real bug caught here: `route(String(promptLength), 1)`
  // checked the digit-count of the length instead of the prompt's actual
  // length, so the long-prompt-routes-to-Opus branch was dead code for
  // every message regardless of how long it actually was).
  const promptText = typeof lastUserText?.content === 'string' ? lastUserText.content : ''
  const model = route(promptText, 1)
  // Two blocks, not one: the static identity/rules text is marked `cache_control:
  // ephemeral` (port of LEO/AI/Prompts/SystemPrompt.swift's two-block caching
  // design) so Anthropic can skip re-processing it on every turn of a
  // conversation; the current date/time is deliberately a separate, uncached
  // block — folding it into the cached text would change that text on every
  // single request and silently defeat the cache while still claiming to use it.
  const system: SystemBlock[] = [
    { type: 'text', text: buildSystemPrompt(), cache_control: { type: 'ephemeral' } },
    { type: 'text', text: dynamicContextBlock(new Date().toISOString()) },
  ]
  const requestOptions = { tools: toolDefinitions(), system }

  const textParts: string[] = []
  const toolUses: { id: string; name: string; input: unknown }[] = []
  let stopReason = 'end_turn'
  let sawAnyEvent = false

  for await (const event of stream(apiKey, model, claudeMessages, requestOptions)) {
    sawAnyEvent = true
    console.debug('[ask-leo stream event]', event.type, event)
    if (event.type === 'contentBlockDelta') {
      textParts.push(event.text)
      onTextDelta(event.text)
    } else if (event.type === 'toolUse') {
      try {
        toolUses.push({ id: event.id, name: event.name, input: JSON.parse(event.inputJSON) })
      } catch {
        // Malformed tool-call JSON from the model — skip rather than crash the turn.
      }
    } else if (event.type === 'messageStop') {
      stopReason = event.stopReason
    } else if (event.type === 'error') {
      throw new Error(event.message)
    }
  }

  // Confirmed live: streaming can report stop_reason "tool_use" (proving
  // message_delta parsed fine) while toolUses stays empty — the model DID
  // decide to call a tool, but the incremental SSE reconstruction of that
  // tool_use block (content_block_start → content_block_delta partial_json →
  // content_block_stop) didn't produce it. Rather than surface an error for
  // something the non-streaming API sidesteps entirely, redo this exact turn
  // with send() — it returns the complete content array as one JSON object,
  // no incremental block reconstruction involved.
  if (stopReason === 'tool_use' && toolUses.length === 0 && textParts.length === 0) {
    console.warn('[ask-leo] streaming reported tool_use with 0 captured tool calls — retrying via non-streaming send()')
    const response = await send(apiKey, model, claudeMessages, requestOptions)
    const contentBlocks = response.content
    for (const block of contentBlocks) {
      if (block.type === 'text') onTextDelta(block.text)
    }
    const fallbackToolUses = contentBlocks.filter((b): b is Extract<ContentBlock, { type: 'tool_use' }> => b.type === 'tool_use')
    const { toolResults, diff } = await runToolCalls(fallbackToolUses, onToolStart)
    return {
      contentBlocks,
      toolResults,
      stopReason: response.stopReason ?? 'end_turn',
      diff,
      sawAnyEvent: true,
      textLength: contentBlocks.filter((b) => b.type === 'text').reduce((n, b) => n + (b.type === 'text' ? b.text.length : 0), 0),
      toolCallCount: fallbackToolUses.length,
    }
  }

  if (!sawAnyEvent) {
    // The stream closed having yielded literally nothing — not even a
    // messageStart — which is different from "Claude answered with an empty
    // turn" and points at the proxy/response shape rather than the model.
    console.warn('[ask-leo] stream produced zero SSE events before closing')
  }

  const contentBlocks: ContentBlock[] = []
  if (textParts.length > 0) contentBlocks.push({ type: 'text', text: textParts.join('') })
  for (const toolUse of toolUses) contentBlocks.push({ type: 'tool_use', id: toolUse.id, name: toolUse.name, input: toolUse.input })

  const { toolResults, diff } = await runToolCalls(toolUses, onToolStart)

  return {
    contentBlocks,
    toolResults,
    stopReason,
    diff,
    sawAnyEvent,
    textLength: textParts.join('').length,
    toolCallCount: toolUses.length,
  }
}

const MAX_TOOL_LOOP_TURNS = 5

/**
 * Runs the full send -> (tool calls -> tool results)* -> final-text loop for
 * one user message, streaming assistant text into the chat store as it
 * arrives. Capped at MAX_TOOL_LOOP_TURNS to guarantee termination even if
 * the model keeps requesting tools indefinitely.
 */
export async function sendUserMessage(userText: string, attachments: PendingAttachment[] = []): Promise<void> {
  // On-device mode is a deliberately separate, much simpler path — no tools,
  // no attachments, no prompt caching (see webllmClient.ts's doc comment for
  // why: Llama-3.2-3B isn't reliable enough at the multi-tool JSON generation
  // the loop below depends on). Attachments are silently dropped here rather
  // than erroring — ChatPage.tsx disables the attach buttons for this
  // provider, so in practice this path is never reached with any.
  if (getProvider() === 'webllm') {
    return sendUserMessageWebLLM(userText)
  }

  const apiKey = loadStoredApiKey()
  if (!apiKey) throw new Error('No Claude API key set — add one in Settings first.')

  const store = useChatStore.getState()

  // Hybrid OCR: run on-device recognition first; only send text (not image
  // bytes) to Claude when it succeeds — mirrors AssistantChatViewModel.swift's
  // VisionOCRService-first design. PDFs skip this entirely (Claude reads
  // those natively, no local extraction step exists or is needed for them).
  const imageAttachment = attachments.find((a) => a.kind === 'image')
  const otherAttachments = attachments.filter((a) => a.kind !== 'image')
  let ocrText: string | undefined
  let ocrSucceeded = false
  let resolvedAttachments = otherAttachments
  if (imageAttachment) {
    const recognized = await recognizeText(imageAttachment.base64, imageAttachment.mimeType)
    if (recognized) {
      ocrText = recognized
      ocrSucceeded = true
      // Image bytes deliberately never reach Claude on this path — only the
      // extracted text does (see buildMessageContent).
    } else {
      ocrText = 'Could not read locally — sending to Claude Vision instead.'
      resolvedAttachments = [...otherAttachments, imageAttachment]
    }
  }

  const userMessage: ChatMessage = {
    id: crypto.randomUUID(),
    role: 'user',
    text: userText,
    createdAt: new Date().toISOString(),
    attachments: resolvedAttachments.length > 0 ? resolvedAttachments.map((a): ChatAttachment => ({ id: crypto.randomUUID(), ...a })) : undefined,
    imagePreview: imageAttachment?.base64,
    ocrText,
    ocrSucceeded,
  }
  store.addMessage(userMessage)

  const assistantMessageId = crypto.randomUUID()
  store.addMessage({ id: assistantMessageId, role: 'assistant', text: '', createdAt: new Date().toISOString() })

  // getActiveMessages() reads live state at call time — reading `store.messages`
  // here (a `getState()` snapshot captured before the two addMessage() calls
  // above) would be stale: it wouldn't include the user message just added,
  // and on a brand-new conversation would be `[]` entirely, sending Claude an
  // empty messages array. See chatStore.ts's doc comment on getActiveMessages.
  let claudeMessages: Message[] = store
    .getActiveMessages()
    .filter((m) => m.id !== assistantMessageId)
    .map((m) => ({ role: m.role, content: buildMessageContent(m) }))

  let accumulatedText = ''
  let diff: DiffPayload | null = null
  let exhaustedTurnLoop = true
  let lastResult: TurnResult | undefined

  try {
    for (let turn = 0; turn < MAX_TOOL_LOOP_TURNS; turn++) {
      const result = await runOneAssistantTurn(
        apiKey,
        claudeMessages,
        (delta) => {
          accumulatedText += delta
          // Text has started arriving — no longer "using a tool," clear the
          // activity label so the UI doesn't keep showing a stale "Checking
          // your schedule…" underneath text that's already streaming in.
          store.updateMessage(assistantMessageId, { text: accumulatedText, activeTool: undefined })
        },
        (toolName) => {
          store.updateMessage(assistantMessageId, { activeTool: toolName })
        },
      )
      lastResult = result
      if (result.diff) diff = result.diff
      claudeMessages = [...claudeMessages, { role: 'assistant', content: result.contentBlocks }]

      if (result.stopReason !== 'tool_use' || result.toolResults.length === 0) {
        exhaustedTurnLoop = false
        break
      }
      claudeMessages = [...claudeMessages, { role: 'user', content: result.toolResults }]
    }
  } catch (err) {
    // Without this, a failed turn left the empty placeholder added above
    // stuck in the store forever, rendering as "…" with no indication
    // anything went wrong — caught live via a bad API key.
    const message = err instanceof Error ? err.message : String(err)
    store.updateMessage(assistantMessageId, { text: accumulatedText, activeTool: undefined, error: message })
    throw err
  }

  if (exhaustedTurnLoop) {
    // Ran all MAX_TOOL_LOOP_TURNS without ever settling into a final,
    // non-tool-call turn — without this, the placeholder was left exactly
    // as empty as a genuine mid-request failure, but silently, since no
    // exception was ever thrown to hit the catch block above.
    store.updateMessage(assistantMessageId, {
      text: accumulatedText,
      activeTool: undefined,
      error: 'LEO kept calling tools without giving a final answer — try rephrasing your question.',
    })
    return
  }

  if (!accumulatedText && !diff) {
    // A turn can legitimately end with stop_reason "end_turn" and zero text
    // (no exception, nothing to catch) — without this, that resolves
    // "successfully" into a permanently empty message, indistinguishable
    // from "still streaming" in the UI.
    if (lastResult?.stopReason === 'max_tokens') {
      // Confirmed live: the model was cut off mid-generation — most likely
      // partway through a tool_use block's JSON (e.g. propose_cancel with a
      // long `ids` array) — before content_block_stop ever fired, so nothing
      // it had produced so far was usable, even though it "succeeded" in the
      // sense that no error was thrown. Worth a distinct message from the
      // generic empty-response case: this one has an actual fix (ask for
      // less at once), not just "try again and hope."
      store.updateMessage(assistantMessageId, {
        text: '',
        activeTool: undefined,
        error: 'LEO ran out of room mid-response (likely while building a large change) — try asking for fewer things at once.',
      })
      return
    }
    // The diagnostic suffix distinguishes "Claude really did answer with
    // nothing" (sawAnyEvent: true, 0 tool calls, stop_reason end_turn) from
    // "the stream got cut off or parsed wrong" (sawAnyEvent: false) —
    // without a real API key to reproduce this against, this is what turns
    // the next report into an actual diagnosis instead of more guessing.
    const diag = lastResult
      ? ` (diagnostic: sawEvents=${lastResult.sawAnyEvent}, stopReason=${lastResult.stopReason}, toolCalls=${lastResult.toolCallCount}, textLen=${lastResult.textLength})`
      : ' (diagnostic: no turn completed at all)'
    store.updateMessage(assistantMessageId, { text: '', activeTool: undefined, error: `LEO returned an empty response — try asking again.${diag}` })
    return
  }

  store.updateMessage(assistantMessageId, { text: accumulatedText, activeTool: undefined, pendingDiff: diff ?? undefined })
}

// Folded into the latest user turn's text rather than sent as a `system`
// message — WebLLM's Hermes tool-calling path injects its own hardcoded
// system prompt (with the live tool list baked in) whenever `tools` is
// present, and throws if the request already contains a system message (see
// webllmClient.ts). Re-sent every turn rather than once, since only the
// latest user message is touched, not the stored history.
const WEBLLM_PERSONA_PREFIX =
  "You are LEO, an on-device assistant with tools for the user's schedule and fitness data. Use a tool whenever the user asks about their data or wants something changed — propose tools return a diff for the user to review, they never apply anything directly. Once you have what you need (or need nothing), reply to the user directly and concisely.\n\n---\n\n"

// See its use below — this model's total context window is 4096 tokens.
const WEBLLM_HISTORY_LIMIT = 6

/** On-device counterpart to the loop above — a separate function rather than
 *  a branch inside it because the request/response shapes are different
 *  enough (OpenAI-style tool_calls vs. Anthropic content blocks, no prompt
 *  caching, no attachments) that sharing one loop would mean threading
 *  provider-specific cases through nearly every line of it.
 *
 *  Two-phase rather than Claude's single interleaved loop: WebLLM's Hermes
 *  tool-calling forces the ENTIRE response into raw tool-call JSON whenever
 *  `tools` is attached to a request — there's no "decide not to call a tool,
 *  just answer in English" within that same call (see webllmClient.ts's doc
 *  comment). So phase 1 loops WITH tools attached purely to let the model
 *  call tools (its streamed "text" during this phase is that JSON, never
 *  shown to the user); once it stops calling tools, phase 2 makes one final
 *  call WITHOUT tools so the model is free to actually reply in prose. Real
 *  cost: every turn is at least two full model calls, not one — slower than
 *  Claude mode by more than just "smaller model," but there's no way to get
 *  both tool-calling and a prose reply out of one Hermes call. */
async function sendUserMessageWebLLM(userText: string): Promise<void> {
  const store = useChatStore.getState()

  const userMessage: ChatMessage = { id: crypto.randomUUID(), role: 'user', text: userText, createdAt: new Date().toISOString() }
  store.addMessage(userMessage)

  const assistantMessageId = crypto.randomUUID()
  store.addMessage({ id: assistantMessageId, role: 'assistant', text: '', createdAt: new Date().toISOString() })

  // Same staleness reasoning as the Claude path — see chatStore.ts's doc
  // comment on getActiveMessages for why this must be a live read, not a
  // snapshot taken before the two addMessage() calls above.
  //
  // Trimmed to the last WEBLLM_HISTORY_LIMIT messages — this model's whole
  // context window is 4096 tokens (see webllmClient.ts's resetChat() doc
  // comment), and the tool-definitions system prompt WebLLM injects on every
  // tool-attached call already eats a real chunk of that on its own. An
  // unbounded conversation would eventually blow the budget within a single
  // call regardless of the cross-call KV-cache reset — this is a deliberate
  // trade of long-conversation recall for not hard-failing.
  const history = store.getActiveMessages().filter((m) => m.id !== assistantMessageId).slice(-WEBLLM_HISTORY_LIMIT)

  let webllmMessages: ChatCompletionMessageParam[] = history.map((m, i) => ({
    role: m.role,
    content: i === history.length - 1 && m.role === 'user' ? `${WEBLLM_PERSONA_PREFIX}${m.text}` : m.text,
  }))

  const onLoadProgress = (report: { progress: number }) => {
    // Writes straight into `text`, not `activeTool` — `activeTool` feeds
    // ChatMessage.tsx's toolActivityLabel(), which is keyed to fixed tool
    // names and would mangle a percentage that changes on every callback.
    // The first real content delta (phase 2) overwrites this before it's
    // ever shown as a final answer, so there's no risk of the two fighting
    // over the field.
    store.updateMessage(assistantMessageId, { text: `Loading on-device model… ${Math.round(report.progress * 100)}%` })
  }

  let accumulatedText = ''
  let diff: DiffPayload | null = null
  let toolLoopExceeded = false

  try {
    // Phase 1: let the model call tools, executing each and feeding the
    // result back, until it stops asking for more (or the turn cap hits).
    for (let turn = 0; turn < MAX_TOOL_LOOP_TURNS; turn++) {
      let turnRawText = ''
      const toolUses: { id: string; name: string; input: unknown }[] = []

      for await (const event of webllmStream(webllmMessages, toolDefinitions(), onLoadProgress)) {
        if (event.type === 'contentBlockDelta') {
          // Deliberately NOT shown to the user or added to accumulatedText —
          // this is the raw tool-call JSON Hermes is forced to generate
          // whenever `tools` is attached, not a real reply. Captured anyway
          // because the assistant message appended below needs a non-null
          // string `content` (WebLLM's own conversation-history renderer
          // requires it), and reusing exactly what the model produced keeps
          // that history faithful to the real exchange.
          turnRawText += event.text
        } else if (event.type === 'toolUse') {
          try {
            toolUses.push({ id: event.id, name: event.name, input: JSON.parse(event.inputJSON) })
          } catch {
            // Malformed tool-call JSON from the model — skip rather than crash the turn (same as the Claude path).
          }
        } else if (event.type === 'error') {
          throw new Error(event.message)
        }
      }

      if (toolUses.length === 0) break // model decided no (more) tools are needed — nothing to append, move to phase 2

      webllmMessages = [
        ...webllmMessages,
        {
          role: 'assistant',
          content: turnRawText,
          tool_calls: toolUses.map((t) => ({ id: t.id, type: 'function' as const, function: { name: t.name, arguments: JSON.stringify(t.input) } })),
        },
      ]

      for (const toolUse of toolUses) {
        store.updateMessage(assistantMessageId, { activeTool: toolUse.name })
        const { result, isError } = await executeTool(toolUse.name, JSON.stringify(toolUse.input))
        webllmMessages = [...webllmMessages, { role: 'tool', tool_call_id: toolUse.id, content: result }]
        if (!diff && !isError) {
          try {
            const parsed = JSON.parse(result)
            if (isDiffPayload(parsed)) diff = parsed
          } catch {
            // Tool result wasn't JSON at all — leave diff unset.
          }
        }
      }
      store.updateMessage(assistantMessageId, { activeTool: undefined })

      if (turn === MAX_TOOL_LOOP_TURNS - 1) toolLoopExceeded = true
    }

    // Phase 2: no `tools` this time — the one call in this whole turn where
    // the model is actually free to respond in prose instead of forced JSON.
    if (!toolLoopExceeded) {
      for await (const event of webllmStream(webllmMessages, undefined, onLoadProgress)) {
        if (event.type === 'contentBlockDelta') {
          accumulatedText += event.text
          store.updateMessage(assistantMessageId, { text: accumulatedText, activeTool: undefined })
        } else if (event.type === 'error') {
          throw new Error(event.message)
        }
      }
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    store.updateMessage(assistantMessageId, { text: accumulatedText, activeTool: undefined, error: message })
    throw err
  }

  if (toolLoopExceeded) {
    store.updateMessage(assistantMessageId, {
      text: accumulatedText,
      activeTool: undefined,
      error: 'LEO kept calling tools without giving a final answer — try rephrasing your question.',
    })
    return
  }

  if (!accumulatedText && !diff) {
    store.updateMessage(assistantMessageId, { text: '', activeTool: undefined, error: 'The on-device model returned an empty response — try asking again.' })
    return
  }

  store.updateMessage(assistantMessageId, { text: accumulatedText, activeTool: undefined, pendingDiff: diff ?? undefined })
}
