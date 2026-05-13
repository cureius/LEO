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
    let timestamp: Date

    static func user(_ text: String, imageData: Data? = nil, ocrText: String? = nil) -> ChatMessage {
        ChatMessage(id: UUID(), role: .user, text: text, isStreaming: false,
                    imageData: imageData, ocrText: ocrText, timestamp: .now)
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

        // Require either text or an image
        let hasContent = !rawPrompt.isEmpty || imageData != nil
        guard hasContent, !isSending else { return }

        // Default prompt when only an image is attached
        let prompt = rawPrompt.isEmpty ? "Read my handwritten notes and create tasks or events from them." : rawPrompt

        inputText = ""
        pendingImageData = nil
        isSending = true
        errorMessage = nil

        // ── Hybrid OCR: run on-device Vision first; only send text (not pixels) to Claude ──
        var userContent: [ContentBlock] = []
        var displayOCRText: String? = nil

        // Build the display message — shown immediately while OCR processes
        var displayMsg = ChatMessage.user(prompt, imageData: imageData)
        messages.append(displayMsg)

        if let jpeg = imageData {
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

            // Agentic loop: stream → handle tool calls → follow-up, up to 6 rounds
            var loopCount = 0
            while loopCount < 6 {
                loopCount += 1

                var streamedText = ""
                var pendingCalls: [(id: String, name: String, inputJSON: String)] = []

                let stream = await client.stream(messages: conversationHistory, tools: tools, system: system)
                for try await event in stream {
                    switch event {
                    case .contentBlockDelta(_, let text):
                        streamedText += text
                        messages[assistantIdx].text = streamedText

                    case .toolUse(let id, let name, let inputJSON):
                        pendingCalls.append((id: id, name: name, inputJSON: inputJSON))

                    case .messageStop:
                        messages[assistantIdx].isStreaming = false

                    case .error(let msg):
                        errorMessage = msg

                    default: break
                    }
                }

                if pendingCalls.isEmpty {
                    // Final turn — persist and finish
                    if !streamedText.isEmpty {
                        conversationHistory.append(Message.assistant(streamedText))
                        await store.appendMessage(
                            PersistedMessage(
                                id: messages[assistantIdx].id,
                                role: .assistant,
                                text: streamedText,
                                timestamp: messages[assistantIdx].timestamp
                            ),
                            to: sessionID
                        )
                    }
                    break
                }

                // Build assistant content blocks (text + all tool_use blocks)
                var assistantContent: [ContentBlock] = []
                if !streamedText.isEmpty {
                    assistantContent.append(.text(TextBlock(text: streamedText)))
                }
                for call in pendingCalls {
                    assistantContent.append(.toolUse(ToolUseBlock(
                        type: "tool_use", id: call.id, name: call.name,
                        input: parseJSONValue(call.inputJSON)
                    )))
                }
                conversationHistory.append(Message(role: .assistant, content: assistantContent))

                // Execute tools; all results go into one user message
                var toolResults: [ContentBlock] = []
                for call in pendingCalls {
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
                        // Persist the proposal so it survives session reload
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
                conversationHistory.append(Message(role: .user, content: toolResults))

                // Reset bubble for the follow-up response
                messages[assistantIdx].text = ""
                messages[assistantIdx].isStreaming = true
            }

        } catch {
            messages[assistantIdx].text = ""
            messages[assistantIdx].isStreaming = false
            errorMessage = error.localizedDescription
            logger.error("Chat send failed: \(error)")
        }

        isSending = false
    }

    private func parseJSONValue(_ string: String) -> JSONValue {
        guard let data = string.data(using: .utf8) else { return .object([:]) }
        return (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .object([:])
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
