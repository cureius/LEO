import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "assistant-chat")

// MARK: - Chat message (display model)

struct ChatMessage: Identifiable, Sendable {
    enum Role: Sendable { case user, assistant, toolCall, diffProposal }
    let id: UUID
    let role: Role
    var text: String
    var isStreaming: Bool
    var diff: DiffPayload?
    var isApplied: Bool = false  // true once the proposal was confirmed by the user
    var imageData: Data?         // JPEG thumbnail for display (user messages only)
    var ocrText: String? = nil   // text extracted on-device; nil when image was sent to Claude
    var documentName: String? = nil  // filename shown for a PDF attachment (user messages only)
    let timestamp: Date

    static func user(_ text: String, imageData: Data? = nil, ocrText: String? = nil, documentName: String? = nil) -> ChatMessage {
        ChatMessage(id: UUID(), role: .user, text: text, isStreaming: false,
                    imageData: imageData, ocrText: ocrText, documentName: documentName, timestamp: .now)
    }
    static func assistant(_ text: String = "", streaming: Bool = false) -> ChatMessage {
        ChatMessage(id: UUID(), role: .assistant, text: text, isStreaming: streaming, timestamp: .now)
    }
    static func proposal(_ diff: DiffPayload) -> ChatMessage {
        ChatMessage(id: UUID(), role: .diffProposal, text: diff.rationale, isStreaming: false, diff: diff, timestamp: .now)
    }
    static func fromPersisted(_ p: PersistedMessage) -> ChatMessage {
        switch p.role {
        case .diffProposal:
            if let diff = p.diff {
                return ChatMessage(id: p.id, role: .diffProposal, text: p.text,
                                   isStreaming: false, diff: diff,
                                   isApplied: p.isApplied, timestamp: p.timestamp)
            }
            fallthrough
        case .assistant:
            return ChatMessage(id: p.id, role: .assistant, text: p.text,
                               isStreaming: false, timestamp: p.timestamp)
        case .user:
            return ChatMessage(id: p.id, role: .user, text: p.text,
                               isStreaming: false, timestamp: p.timestamp)
        }
    }
}

// MARK: - AssistantChatViewModel

@Observable
@MainActor
final class AssistantChatViewModel {
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isSending = false
    var errorMessage: String? = nil
    var pendingImageData: Data? = nil   // JPEG data for the queued photo
    var pendingDocumentData: Data? = nil   // PDF bytes for the queued document
    var pendingDocumentName: String? = nil

    let sessionID: UUID
    let suggestions = [
        "What's on my schedule today?",
        "Find me 90 min for deep work",
        "I'm swamped — what can I push?",
        "Plan my week"
    ]

    private let client: ClaudeClient
    private let toolRuntime: ToolRuntime
    private let itemRepository: ItemRepository
    private let store: ConversationStore
    private var conversationHistory: [Message] = []

    init(
        sessionID: UUID,
        client: ClaudeClient,
        toolRuntime: ToolRuntime,
        itemRepository: ItemRepository,
        store: ConversationStore = .shared
    ) {
        self.sessionID = sessionID
        self.client = client
        self.toolRuntime = toolRuntime
        self.itemRepository = itemRepository
        self.store = store
    }

    // MARK: - Load existing session messages

    func loadHistory() async {
        guard let session = await store.session(id: sessionID) else { return }
        messages = session.messages.map { ChatMessage.fromPersisted($0) }
        // Reconstruct API conversation history — exclude diffProposal (not sent to Claude)
        conversationHistory = session.messages.compactMap { msg in
            switch msg.role {
            case .user:         return Message.user(msg.text)
            case .assistant:    return Message.assistant(msg.text)
            case .diffProposal: return nil
            }
        }
    }

    // MARK: - Send

    func send(_ text: String? = nil) async {
        let rawPrompt = (text ?? inputText).trimmingCharacters(in: .whitespaces)
        let imageData = pendingImageData
        let documentData = pendingDocumentData
        let documentName = pendingDocumentName

        // Require text, an image, or a document
        let hasContent = !rawPrompt.isEmpty || imageData != nil || documentData != nil
        guard hasContent, !isSending else { return }

        // Default prompt when only an attachment is present
        let prompt: String
        if !rawPrompt.isEmpty {
            prompt = rawPrompt
        } else if documentData != nil {
            prompt = "Read this document and summarize it, or create tasks/events from it."
        } else {
            prompt = "Read my handwritten notes and create tasks or events from them."
        }

        inputText = ""
        pendingImageData = nil
        pendingDocumentData = nil
        pendingDocumentName = nil
        isSending = true
        errorMessage = nil

        // ── Hybrid OCR: run on-device Vision first; only send text (not pixels) to Claude ──
        var userContent: [ContentBlock] = []
        var displayOCRText: String? = nil

        // Build the display message — shown immediately while OCR processes
        var displayMsg = ChatMessage.user(prompt, imageData: imageData, documentName: documentName)
        messages.append(displayMsg)

        if let pdf = documentData {
            // No OCR step for documents — Claude reads PDFs natively (text,
            // tables, layout, embedded images), same as apps/web's document
            // content block.
            userContent.append(.document(DocumentBlock(pdfData: pdf)))
            userContent.append(.text(TextBlock(text: prompt)))
        } else if let jpeg = imageData {
            #if os(iOS)
            let extracted = await VisionOCRService.shared.recognizeText(from: jpeg)
            #else
            let extracted: String? = nil
            #endif

            if let text = extracted {
                // ✅ OCR succeeded — only the extracted text goes to Claude (no image tokens)
                displayOCRText = text
                let fullPrompt = """
                I photographed some handwritten notes. Here is the text extracted on-device:

                ---
                \(text)
                ---

                \(prompt)
                """
                userContent.append(.text(TextBlock(text: fullPrompt)))
            } else {
                // ⚠️ OCR found nothing readable — fall back to Claude Vision (image sent to API)
                displayOCRText = "Could not read locally — sending to Claude Vision instead."
                userContent.append(.image(ImageBlock(jpegData: jpeg)))
                userContent.append(.text(TextBlock(text: prompt)))
            }

            // Update the display bubble with the OCR outcome
            if let idx = messages.firstIndex(where: { $0.id == displayMsg.id }) {
                messages[idx].ocrText = displayOCRText
                displayMsg = messages[idx]
            }
        } else {
            userContent.append(.text(TextBlock(text: prompt)))
        }

        conversationHistory.append(Message(role: .user, content: userContent))
        await store.appendMessage(
            PersistedMessage(id: displayMsg.id, role: .user, text: prompt, timestamp: displayMsg.timestamp),
            to: sessionID
        )

        // Single streaming assistant bubble that we update in-place
        let assistantMsg = ChatMessage.assistant(streaming: true)
        messages.append(assistantMsg)
        let assistantIdx = messages.count - 1

        do {
            let items = (try? await itemRepository.fetch()) ?? []
            let system = [SystemPrompt.identityBlock, SystemPrompt.standingContextBlock(items: items)]
            let tools = await toolRuntime.toolDefinitions

            // Agentic loop: stream → handle tool calls → follow-up, capped so a model
            // that keeps requesting tools indefinitely can't hang the turn forever.
            // Port of apps/web/src/ai/chatOrchestrator.ts's sendUserMessage loop —
            // same MAX_TOOL_LOOP_TURNS, same three previously-silent failure modes
            // it exists to catch (see the three branches after the loop below).
            var exhaustedTurnLoop = true
            var lastResult: TurnResult?

            for _ in 0..<Self.maxToolLoopTurns {
                let result = try await runOneAssistantTurn(
                    tools: tools, system: system, assistantIdx: assistantIdx
                )
                lastResult = result

                if result.stopReason != "tool_use" || result.pendingCalls.isEmpty {
                    exhaustedTurnLoop = false
                    if !result.text.isEmpty {
                        conversationHistory.append(Message.assistant(result.text))
                        await store.appendMessage(
                            PersistedMessage(
                                id: messages[assistantIdx].id,
                                role: .assistant,
                                text: result.text,
                                timestamp: messages[assistantIdx].timestamp
                            ),
                            to: sessionID
                        )
                    }
                    break
                }

                // Build assistant content blocks (text + all tool_use blocks)
                var assistantContent: [ContentBlock] = []
                if !result.text.isEmpty {
                    assistantContent.append(.text(TextBlock(text: result.text)))
                }
                for call in result.pendingCalls {
                    assistantContent.append(.toolUse(ToolUseBlock(
                        type: "tool_use", id: call.id, name: call.name,
                        input: parseJSONValue(call.inputJSON)
                    )))
                }
                conversationHistory.append(Message(role: .assistant, content: assistantContent))

                let toolResults = await runToolCalls(result.pendingCalls)
                conversationHistory.append(Message(role: .user, content: toolResults))

                // Reset bubble for the follow-up response
                messages[assistantIdx].text = ""
                messages[assistantIdx].isStreaming = true
            }

            if exhaustedTurnLoop {
                // Ran every turn without ever settling into a final, non-tool-call
                // response — previously this left the bubble exactly as empty as a
                // genuine mid-request failure, but silently, since nothing threw.
                messages[assistantIdx].text = ""
                messages[assistantIdx].isStreaming = false
                errorMessage = "LEO kept calling tools without giving a final answer — try rephrasing your question."
            } else if messages[assistantIdx].text.isEmpty {
                // A turn can legitimately end with stop_reason "end_turn" (or
                // "max_tokens") and zero text — no exception, nothing to catch.
                // Without this, that resolved "successfully" into a permanently
                // empty bubble, indistinguishable from "still streaming."
                messages[assistantIdx].isStreaming = false
                if lastResult?.stopReason == "max_tokens" {
                    // Confirmed live (web): the model was cut off mid-generation —
                    // most likely partway through a large tool_use block's JSON —
                    // before it produced anything usable, even though no error was
                    // thrown. Distinct message since this one has an actual fix
                    // (ask for less at once), unlike the generic empty-response case.
                    errorMessage = "LEO ran out of room mid-response (likely while building a large change) — try asking for fewer things at once."
                } else {
                    let diag = lastResult.map {
                        " (diagnostic: sawEvents=\($0.sawAnyEvent), stopReason=\($0.stopReason), toolCalls=\($0.toolCallCount), textLen=\($0.textLength))"
                    } ?? " (diagnostic: no turn completed at all)"
                    errorMessage = "LEO returned an empty response — try asking again.\(diag)"
                }
            }

        } catch {
            messages[assistantIdx].text = ""
            messages[assistantIdx].isStreaming = false
            errorMessage = error.localizedDescription
            logger.error("Chat send failed: \(error)")
        }

        isSending = false
    }

    private static let maxToolLoopTurns = 5

    private struct TurnResult {
        var text: String
        var pendingCalls: [(id: String, name: String, inputJSON: String)]
        var stopReason: String
        var sawAnyEvent: Bool
        var textLength: Int
        var toolCallCount: Int
    }

    /// Streams one assistant turn. If the model signals `stop_reason: "tool_use"`
    /// but the incremental SSE reconstruction produced zero tool calls AND zero
    /// text — confirmed live (web): a real gap where the model genuinely decided
    /// to call a tool but the streaming content_block_start/delta/stop
    /// reconstruction didn't produce it — retries the exact same turn via the
    /// non-streaming `send()`, which returns the complete content array as one
    /// JSON object with no incremental reconstruction involved.
    private func runOneAssistantTurn(
        tools: [ToolDefinition], system: [SystemBlock], assistantIdx: Int
    ) async throws -> TurnResult {
        var streamedText = ""
        var pendingCalls: [(id: String, name: String, inputJSON: String)] = []
        var stopReason = "end_turn"
        var sawAnyEvent = false

        let stream = await client.stream(messages: conversationHistory, tools: tools, system: system)
        for try await event in stream {
            sawAnyEvent = true
            switch event {
            case .contentBlockDelta(_, let text):
                streamedText += text
                messages[assistantIdx].text = streamedText

            case .toolUse(let id, let name, let inputJSON):
                pendingCalls.append((id: id, name: name, inputJSON: inputJSON))

            case .messageStop(let reason, _):
                stopReason = reason
                messages[assistantIdx].isStreaming = false

            case .error(let msg):
                errorMessage = msg

            default: break
            }
        }

        if stopReason == "tool_use" && pendingCalls.isEmpty && streamedText.isEmpty {
            logger.warning("streaming reported tool_use with 0 captured tool calls — retrying via non-streaming send()")
            let response = try await client.send(messages: conversationHistory, tools: tools, system: system)
            for block in response.content {
                if case .text(let t) = block {
                    streamedText += t.text
                    messages[assistantIdx].text = streamedText
                }
            }
            let fallbackCalls: [(id: String, name: String, inputJSON: String)] = response.content.compactMap { block in
                guard case .toolUse(let tu) = block else { return nil }
                return (id: tu.id, name: tu.name, inputJSON: encodeJSONValueToString(tu.input))
            }
            return TurnResult(
                text: streamedText, pendingCalls: fallbackCalls,
                stopReason: response.stopReason ?? "end_turn",
                sawAnyEvent: true, textLength: streamedText.count, toolCallCount: fallbackCalls.count
            )
        }

        return TurnResult(
            text: streamedText, pendingCalls: pendingCalls, stopReason: stopReason,
            sawAnyEvent: sawAnyEvent, textLength: streamedText.count, toolCallCount: pendingCalls.count
        )
    }

    /// Executes every pending tool call, appending a "Used tool: X" bubble and
    /// detecting/persisting any diff proposal — shared by both the normal
    /// streaming path and runOneAssistantTurn's non-streaming fallback, so a
    /// tool call recovered via the fallback still gets the same UI treatment.
    private func runToolCalls(_ calls: [(id: String, name: String, inputJSON: String)]) async -> [ContentBlock] {
        var toolResults: [ContentBlock] = []
        for call in calls {
            let (result, isError) = await toolRuntime.execute(name: call.name, inputJSON: call.inputJSON)
            messages.append(ChatMessage(
                id: UUID(), role: .toolCall,
                text: "Used tool: \(call.name)", isStreaming: false, timestamp: .now
            ))
            toolResults.append(.toolResult(ToolResultBlock(
                toolUseId: call.id, content: result, isError: isError
            )))
            if let data = result.data(using: .utf8),
               let payload = try? JSONDecoder().decode(WrappedDiff.self, from: data) {
                let proposalMsg = ChatMessage.proposal(payload.diff)
                messages.append(proposalMsg)
                await store.appendMessage(
                    PersistedMessage(
                        id: proposalMsg.id,
                        role: .diffProposal,
                        text: payload.diff.rationale,
                        timestamp: proposalMsg.timestamp,
                        diff: payload.diff
                    ),
                    to: sessionID
                )
            }
        }
        return toolResults
    }

    private func parseJSONValue(_ string: String) -> JSONValue {
        guard let data = string.data(using: .utf8) else { return .object([:]) }
        return (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .object([:])
    }

    /// Inverse of `parseJSONValue` — needed for the non-streaming fallback in
    /// `runOneAssistantTurn`, whose `send()` response already gives a typed
    /// `ToolUseBlock.input: JSONValue` rather than a raw JSON string, but
    /// `toolRuntime.execute(name:inputJSON:)` needs a String either way.
    private func encodeJSONValueToString(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    /// Mark a proposal as applied so it shows as done after the session is reloaded.
    func markProposalApplied(id: UUID) async {
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].isApplied = true
        }
        if var session = await store.session(id: sessionID),
           let idx = session.messages.firstIndex(where: { $0.id == id }) {
            session.messages[idx].isApplied = true
            await store.save(session)
        }
    }

    func clearHistory() async {
        messages.removeAll()
        conversationHistory.removeAll()
        // Wipe persisted messages and reset the session title
        if var session = await store.session(id: sessionID) {
            session.messages = []
            session.title = "New chat"
            await store.save(session)
        }
    }

    private struct WrappedDiff: Decodable { let diff: DiffPayload }
}
