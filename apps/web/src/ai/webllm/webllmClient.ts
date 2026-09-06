import type { ChatCompletionMessageParam, ChatCompletionTool } from '@mlc-ai/web-llm'
import type { StreamEvent, ToolDefinition } from '../models'
import { getEngine, type EngineLoadProgress } from './engine'

/**
 * On-device counterpart to claudeClient.ts's stream() — yields the same
 * StreamEvent shape so chatOrchestrator.ts's UI-facing plumbing (text deltas,
 * tool_use events) doesn't need a second rendering path, but the request/
 * response translation underneath is meaningfully different: WebLLM's tool-
 * calling support (Hermes-3-Llama-3.1-8B, see engine.ts) never streams
 * partial tool-call JSON — it only knows the full call once generation
 * finishes, and hands it back on the FINAL chunk, already-parsed, as a
 * `delta.tool_calls` array with no `id` (WebLLM doesn't assign one in
 * streaming mode) — ids are synthesized here instead. Reliability is real:
 * this is an 8B local model doing free-form JSON generation guided by a
 * prompt-injected tool list, not Claude's native, far more reliable tool use.
 *
 * Bigger constraint than reliability, though: whenever `tools` is attached,
 * WebLLM forces the ENTIRE response into a JSON array of tool calls
 * (`response_format: json_object` under the hood) — there is no "decide not
 * to call a tool and just reply in English" within that same request. Every
 * `contentBlockDelta` yielded while `tools` is set is that raw JSON being
 * generated token-by-token, never prose meant for a user to read. See
 * chatOrchestrator.ts's two-phase design (tool-decision calls WITH tools,
 * then one final call WITHOUT tools for the actual reply) for how this is
 * worked around — this function itself is deliberately naive about it and
 * always yields whatever the model streams, phase-appropriate filtering is
 * the caller's job.
 */

function toOpenAITool(def: ToolDefinition): ChatCompletionTool {
  return { type: 'function', function: { name: def.name, description: def.description, parameters: def.input_schema } }
}

export async function* stream(
  messages: ChatCompletionMessageParam[],
  tools: ToolDefinition[] | undefined,
  onLoadProgress?: (report: EngineLoadProgress) => void,
): AsyncGenerator<StreamEvent> {
  const engine = await getEngine(onLoadProgress)

  // Confirmed live: "Prompt tokens exceed context window size: ... 862 ...
  // 4096" — a number nowhere near 4096 on its face. This model's shipped
  // config caps context_window_size at 4096 (down from its native 131072,
  // almost certainly to fit its KV cache in less browser VRAM), but
  // MLCEngine keeps that KV cache alive across EVERY call for the life of
  // the loaded engine, not just one turn — the library's real check is
  // `promptTokens + alreadyFilledCache > 4096`, and the error only ever
  // prints promptTokens and the static 4096, never the hidden filled amount,
  // which is why a modest-looking prompt can still "exceed" it. Since every
  // call here already carries the FULL explicit conversation (chatOrchestrator
  // never relies on the engine's own memory of earlier turns), resetting
  // before each call is free correctness-wise — nothing is lost — and trades
  // away prefix-cache reuse (a real, accepted speed cost) for never silently
  // accumulating past a window this tight.
  await engine.resetChat()

  const completion = await engine.chat.completions.create({
    stream: true,
    // A fresh array, not the caller's own — confirmed live: when `tools` is
    // set, WebLLM's Hermes handling does `request.messages.unshift(...)` to
    // inject its own system prompt, which mutates whatever array reference
    // `request.messages` points to. Passing the caller's array directly let
    // that mutation leak back into chatOrchestrator.ts's own copy, so its
    // NEXT call (the tool-result follow-up) saw a stray system message it
    // never added and threw "cannot specify customized system prompt" —
    // the exact bug this fixes.
    messages: [...messages],
    ...(tools && tools.length > 0 ? { tools: tools.map(toOpenAITool) } : {}),
  })

  yield { type: 'messageStart', id: crypto.randomUUID(), model: 'webllm' }

  for await (const chunk of completion) {
    const choice = chunk.choices[0]
    if (typeof choice?.delta?.content === 'string' && choice.delta.content) {
      yield { type: 'contentBlockDelta', index: 0, text: choice.delta.content }
    }
    for (const toolCall of choice?.delta?.tool_calls ?? []) {
      if (!toolCall.function?.name) continue
      yield {
        type: 'toolUse',
        id: `webllm_${toolCall.index}_${crypto.randomUUID().slice(0, 8)}`,
        name: toolCall.function.name,
        inputJSON: toolCall.function.arguments ?? '{}',
      }
    }
    if (choice?.finish_reason) yield { type: 'messageStop', stopReason: choice.finish_reason }
  }
}
