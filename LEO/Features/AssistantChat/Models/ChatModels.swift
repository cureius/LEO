import Foundation

// MARK: - Persisted session

struct ChatSession: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var messages: [PersistedMessage]
    let createdAt: Date
    var updatedAt: Date

    var preview: String {
        messages.last(where: { $0.role == .assistant })?.text.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? messages.last?.text.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "No messages yet"
    }

    var isEmpty: Bool { messages.isEmpty }

    static func create(title: String = "New chat") -> ChatSession {
        ChatSession(id: UUID(), title: title, messages: [], createdAt: .now, updatedAt: .now)
    }
}

// MARK: - Persisted message

struct PersistedMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let role: PersistedRole
    let text: String
    let timestamp: Date
    var diff: DiffPayload?      // populated only for diffProposal role
    var isApplied: Bool = false // true once the user confirmed the diff

    enum PersistedRole: String, Codable { case user, assistant, diffProposal }
}
