import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "claude")

private let anthropicAPIBase = "https://api.anthropic.com/v1/messages"
private let anthropicVersion = "2023-06-01"
private let anthropicBeta = "prompt-caching-2024-07-31"

/// No bytes at all — not even a keepalive — for this long means the connection
/// has stalled. Without a bound on this, a hung `bytes(for:)` call or a stalled
/// `AsyncBytes` read left the caller awaiting forever: the assistant bubble
/// sits at "…" with nothing to catch, since nothing has actually failed yet,
/// it just never finishes. Armed on both the initial connect and every
/// subsequent line read — matches the port of this same fix on the web client
/// (apps/web/src/ai/claudeClient.ts), including the 75s value (originally 30s,
/// raised after a real report of this firing on a legitimate multi-tool query
/// with a non-trivial system prompt, not just a truly hung connection).
private let idleTimeoutSeconds: TimeInterval = 75

/// Was 4096 — raised after a real report of stop_reason "max_tokens" with ZERO
/// captured text or tool calls: the model got cut off mid-generation (most
/// likely partway through a tool_use block's JSON — e.g. propose_cancel with a
/// long `ids` array) before content_block_stop ever fired, so nothing it had
/// generated so far was usable. 4096 is tight for a response that also has to
/// hold a non-trivial tool_use payload; 8192 gives real headroom without being
/// unbounded. Matches apps/web/src/ai/claudeClient.ts's DEFAULT_MAX_TOKENS,
/// which hit and fixed this exact bug first.
private let defaultMaxTokens = 8192

/// Races `operation` against a one-shot idle timer, throwing `.timeout` if the
/// timer wins. Reusable for both "get the initial response" and "read the next
/// line" — both need the same "nothing at all for N seconds is a stall" rule.
private func withIdleTimeout<T: Sendable>(seconds: TimeInterval = idleTimeoutSeconds, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw ClaudeError.timeout
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

/// `AsyncLineSequence`'s iterator is `mutating`, which doesn't fit cleanly into
/// a `@Sendable` closure passed across a task-group boundary. `@unchecked
/// Sendable` is safe here specifically because `withIdleTimeout` only ever has
/// one of its two racing tasks actually call `next()` at a time — the loop
/// always awaits one race before starting the next, never overlapping calls.
private final class LineIteratorBox: @unchecked Sendable {
    private var iterator: AsyncLineSequence<URLSession.AsyncBytes>.AsyncIterator
    init(_ lines: AsyncLineSequence<URLSession.AsyncBytes>) { self.iterator = lines.makeAsyncIterator() }
    func next() async throws -> String? { try await iterator.next() }
}

// MARK: - ClaudeClient

/// Hand-rolled Claude API client. No third-party SDK.
/// Uses URLSession + SSE streaming. Stores API key in Keychain.
actor ClaudeClient {
    private let model: ClaudeModel
    private let session: URLSession
    private var apiKey: String?
    private let telemetry: AITelemetry

    init(model: ClaudeModel = .sonnet46, session: URLSession = .shared, telemetry: AITelemetry = .shared) {
        self.model = model
        self.session = session
        self.telemetry = telemetry
        self.apiKey = KeychainHelper.load(key: "claude_api_key")
        ?? ProcessInfo.processInfo.environment["CLAUDE_API_KEY"]
    }

    func setAPIKey(_ key: String) {
        apiKey = key
        KeychainHelper.save(key: "claude_api_key", value: key)
    }

    func removeAPIKey() {
        apiKey = nil
        KeychainHelper.delete(key: "claude_api_key")
    }

    var hasAPIKey: Bool { apiKey != nil }

    // MARK: - One-shot send

    func send(
        messages: [Message],
        tools: [ToolDefinition]? = nil,
        system: [SystemBlock]? = nil,
        maxTokens: Int = defaultMaxTokens
    ) async throws -> ClaudeResponse {
        guard let key = apiKey else { throw ClaudeError.missingAPIKey }
        let body = try buildRequestBody(messages: messages, tools: tools, system: system, maxTokens: maxTokens, stream: false)
        var req = URLRequest(url: URL(string: anthropicAPIBase)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue(anthropicBeta, forHTTPHeaderField: "anthropic-beta")
        req.httpBody = body
        req.timeoutInterval = 60

        let (data, response) = try await session.data(for: req)
        try checkStatus(response)

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        await telemetry.record(model: model, usage: decoded.usage)
        return decoded
    }

    // MARK: - Streaming send

    func stream(
        messages: [Message],
        tools: [ToolDefinition]? = nil,
        system: [SystemBlock]? = nil,
        maxTokens: Int = defaultMaxTokens
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let key = apiKey else { throw ClaudeError.missingAPIKey }
                    let body = try buildRequestBody(messages: messages, tools: tools, system: system, maxTokens: maxTokens, stream: true)
                    var req = URLRequest(url: URL(string: anthropicAPIBase)!)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue(key, forHTTPHeaderField: "x-api-key")
                    req.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
                    req.setValue(anthropicBeta, forHTTPHeaderField: "anthropic-beta")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.httpBody = body
                    req.timeoutInterval = 120

                    let (bytes, response) = try await withIdleTimeout { try await self.session.bytes(for: req) }
                    try checkStatus(response)

                    var toolInputBuffer: [String: String] = [:]
                    var toolBlockMeta: [String: (id: String, name: String)] = [:]

                    let lineBox = LineIteratorBox(bytes.lines)
                    while let line = try await withIdleTimeout(seconds: idleTimeoutSeconds, { try await lineBox.next() }) {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        let eventType = json["type"] as? String ?? ""
                        switch eventType {
                        case "message_start":
                            let msg = json["message"] as? [String: Any]
                            let id = msg?["id"] as? String ?? ""
                            let model = msg?["model"] as? String ?? ""
                            continuation.yield(.messageStart(id: id, model: model))

                        case "content_block_start":
                            let block = json["content_block"] as? [String: Any]
                            let index = json["index"] as? Int ?? 0
                            if let blockType = block?["type"] as? String, blockType == "tool_use" {
                                let toolID = block?["id"] as? String ?? ""
                                let toolName = block?["name"] as? String ?? ""
                                toolBlockMeta["\(index)"] = (id: toolID, name: toolName)
                            }

                        case "content_block_delta":
                            let delta = json["delta"] as? [String: Any]
                            let index = json["index"] as? Int ?? 0
                            if let text = delta?["text"] as? String {
                                continuation.yield(.contentBlockDelta(index: index, text: text))
                            } else if let partial = delta?["partial_json"] as? String {
                                let blockID = "\(index)"
                                toolInputBuffer[blockID, default: ""] += partial
                            }

                        case "content_block_stop":
                            let index = json["index"] as? Int ?? 0
                            let key = "\(index)"
                            if let accumulated = toolInputBuffer.removeValue(forKey: key),
                               let meta = toolBlockMeta.removeValue(forKey: key) {
                                continuation.yield(.toolUse(id: meta.id, name: meta.name, inputJSON: accumulated))
                            }

                        case "message_delta":
                            let delta = json["delta"] as? [String: Any]
                            let stopReason = delta?["stop_reason"] as? String ?? ""
                            let usage = parseUsage(json["usage"] as? [String: Any])
                            await telemetry.record(model: model, usage: usage)
                            continuation.yield(.messageStop(stopReason: stopReason, usage: usage))

                        case "error":
                            let error = json["error"] as? [String: Any]
                            continuation.yield(.error(error?["message"] as? String ?? "Unknown error"))

                        default: break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private helpers

    private func buildRequestBody(
        messages: [Message],
        tools: [ToolDefinition]?,
        system: [SystemBlock]?,
        maxTokens: Int,
        stream: Bool
    ) throws -> Data {
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": maxTokens,
            "messages": try encodeMessages(messages)
        ]
        if stream { body["stream"] = true }
        if let system = system, !system.isEmpty {
            body["system"] = try encodeSystem(system)
        }
        if let tools = tools, !tools.isEmpty {
            body["tools"] = try encodingTools(tools)
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func encodeMessages(_ messages: [Message]) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(messages)
        return try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
    }

    private func encodeSystem(_ system: [SystemBlock]) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(system)
        return try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
    }

    private func encodingTools(_ tools: [ToolDefinition]) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(tools)
        return try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
    }

    private func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw ClaudeError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
            throw ClaudeError.rateLimited(retryAfter: retryAfter)
        default: throw ClaudeError.serverError(status: http.statusCode)
        }
    }

    private func parseUsage(_ json: [String: Any]?) -> ClaudeResponse.Usage? {
        guard let json else { return nil }
        return ClaudeResponse.Usage(
            inputTokens: json["input_tokens"] as? Int ?? 0,
            outputTokens: json["output_tokens"] as? Int ?? 0,
            cacheCreationInputTokens: json["cache_creation_input_tokens"] as? Int,
            cacheReadInputTokens: json["cache_read_input_tokens"] as? Int
        )
    }
}

// MARK: - Keychain helper

enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
