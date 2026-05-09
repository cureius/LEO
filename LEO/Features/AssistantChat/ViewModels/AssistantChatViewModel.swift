import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "assistant-chat")

// MARK: - Chat message

struct ChatMessage: Identifiable, Sendable {
    enum Role: Sendable { case user, assistant, toolCall, toolResult, diffProposal }
    let id: UUID
    let role: Role
    var text: String
    var isStreaming: Bool
    var diff: DiffPayload?

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(id: UUID(), role: .user, text: text, isStreaming: false)
    }
    static func assistant(_ text: String = "", streaming: Bool = false) -> ChatMessage {
        ChatMessage(id: UUID(), role: .assistant, text: text, isStreaming: streaming)
    }
    static func proposal(_ diff: DiffPayload) -> ChatMessage {
        ChatMessage(id: UUID(), role: .diffProposal, text: diff.rationale, isStreaming: false, diff: diff)
    }
}

// MARK: - AssistantChatViewModel

@Observable
@MainActor
final class AssistantChatViewModel {
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isSending: Bool = false
    var errorMessage: String? = nil
    var pendingDiff: DiffPayload? = nil

    let suggestions = ["Plan my week", "What's my Friday like?", "Find me 90 min for deep work", "I'm sick today — what should I push?"]

    private let client: ClaudeClient
    private let toolRuntime: ToolRuntime
    private let itemRepository: ItemRepository
    private var conversationHistory: [Message] = []

    init(client: ClaudeClient, toolRuntime: ToolRuntime, itemRepository: ItemRepository) {
        self.client = client
        self.toolRuntime = toolRuntime
        self.itemRepository = itemRepository
    }

    // MARK: - Send

    func send(_ text: String? = nil) async {
        let prompt = text ?? inputText.trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty, !isSending else { return }

        inputText = ""
        isSending = true
        errorMessage = nil

        messages.append(.user(prompt))
        conversationHistory.append(Message.user(prompt))

        let assistantMsg = ChatMessage.assistant(streaming: true)
        messages.append(assistantMsg)
        let assistantIndex = messages.count - 1

        do {
            let items = (try? await itemRepository.fetch()) ?? []
            let system = [SystemPrompt.identityBlock, SystemPrompt.standingContextBlock(items: items)]
            let tools = await toolRuntime.toolDefinitions

            var streamedText = ""
            let stream = await client.stream(messages: conversationHistory, tools: tools, system: system)

            for try await event in stream {
                switch event {
                case .contentBlockDelta(_, let text):
                    streamedText += text
                    messages[assistantIndex].text = streamedText

                case .toolUse(let id, let name, let inputJSON):
                    let (result, isError) = await toolRuntime.execute(name: name, inputJSON: inputJSON)
                    messages[assistantIndex].isStreaming = false
                    messages.append(ChatMessage(id: UUID(), role: .toolCall, text: "🔧 \(name)", isStreaming: false))
                    conversationHistory.append(Message(role: .assistant, content: [
                        .toolUse(ToolUseBlock(type: "tool_use", id: id, name: name, input: .object([:])))
                    ]))
                    conversationHistory.append(Message(role: .user, content: [
                        .toolResult(ToolResultBlock(toolUseId: id, content: result, isError: isError))
                    ]))

                    // Check if result contains a Diff
                    if let data = result.data(using: .utf8),
                       let payload = try? JSONDecoder().decode(WrappedDiff.self, from: data) {
                        messages.append(.proposal(payload.diff))
                        pendingDiff = payload.diff
                    }

                case .messageStop:
                    messages[assistantIndex].isStreaming = false

                case .error(let msg):
                    errorMessage = "AI error: \(msg)"

                default: break
                }
            }

            if !streamedText.isEmpty {
                conversationHistory.append(Message.assistant(streamedText))
            }
        } catch {
            messages[assistantIndex].text = "Error: \(error.localizedDescription)"
            messages[assistantIndex].isStreaming = false
            errorMessage = error.localizedDescription
            logger.error("Chat send failed: \(error)")
        }

        isSending = false
    }

    func clearHistory() {
        messages.removeAll()
        conversationHistory.removeAll()
        pendingDiff = nil
    }

    private struct WrappedDiff: Decodable {
        let diff: DiffPayload
    }
}
