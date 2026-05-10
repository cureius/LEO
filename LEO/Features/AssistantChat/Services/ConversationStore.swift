import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "conversations")

// MARK: - ConversationStore

actor ConversationStore {
    static let shared = ConversationStore()

    private var sessions: [ChatSession] = []
    private var isLoaded = false

    private var fileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("leo_chat_sessions.json")
    }

    // MARK: - Public API

    func allSessions() async -> [ChatSession] {
        await ensureLoaded()
        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    func session(id: UUID) async -> ChatSession? {
        await ensureLoaded()
        return sessions.first { $0.id == id }
    }

    func save(_ session: ChatSession) async {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.insert(session, at: 0)
        }
        await persist()
    }

    func delete(id: UUID) async {
        sessions.removeAll { $0.id == id }
        await persist()
    }

    func deleteAll() async {
        sessions.removeAll()
        await persist()
    }

    func appendMessage(_ message: PersistedMessage, to sessionID: UUID) async {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[idx].messages.append(message)
        sessions[idx].updatedAt = .now

        // Auto-title from first user message
        if sessions[idx].messages.count == 1, message.role == .user {
            let raw = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            sessions[idx].title = String(raw.prefix(48))
        }

        await persist()
    }

    // MARK: - Persistence

    private func ensureLoaded() async {
        guard !isLoaded else { return }
        isLoaded = true
        do {
            let data = try Data(contentsOf: fileURL)
            sessions = try JSONDecoder().decode([ChatSession].self, from: data)
            logger.info("Loaded \(self.sessions.count) sessions")
        } catch {
            sessions = []
        }
    }

    private func persist() async {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to persist sessions: \(error)")
        }
    }
}
