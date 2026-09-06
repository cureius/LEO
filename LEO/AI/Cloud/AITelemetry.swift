import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "ai-telemetry")

// MARK: - Telemetry record

struct AIRequestRecord: Codable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    var totalCostUSD: Double {
        // Approximate pricing (USD per MTok) as of 2025 — update before release
        let rates: (inputMTok: Double, outputMTok: Double) = {
            switch model {
            case ClaudeModel.opus47.rawValue:   return (15.0, 75.0)
            case ClaudeModel.sonnet46.rawValue: return (3.0, 15.0)
            default:                            return (0.8, 4.0)  // haiku
            }
        }()
        return (Double(inputTokens) / 1_000_000) * rates.inputMTok
             + (Double(outputTokens) / 1_000_000) * rates.outputMTok
    }
}

// MARK: - AITelemetry actor

actor AITelemetry {
    static let shared = AITelemetry()

    private let storageURL: URL? = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ai_telemetry.json")
    }()

    private var records: [AIRequestRecord] = []

    init() {
        records = load()
    }

    /// Takes `usage` directly rather than a full `ClaudeResponse` so both the
    /// one-shot `send()` path and the streaming `stream()` path (whose usage
    /// only becomes available from the final `message_delta` event, never a
    /// `ClaudeResponse`) can record through the same entry point. Previously
    /// only `send()` called this — `stream()`, the path every normal turn
    /// actually takes, never recorded anything, so the AI Usage screen was
    /// effectively dead for real conversations.
    func record(model: ClaudeModel, usage: ClaudeResponse.Usage?) {
        let r = AIRequestRecord(
            id: UUID(),
            timestamp: .now,
            model: model.rawValue,
            inputTokens: usage?.inputTokens ?? 0,
            outputTokens: usage?.outputTokens ?? 0,
            cacheCreationTokens: usage?.cacheCreationInputTokens ?? 0,
            cacheReadTokens: usage?.cacheReadInputTokens ?? 0
        )
        records.append(r)
        // Rotate if needed
        if records.count > 100 { records.removeFirst(records.count - 100) }
        persist()
        logger.info("AI request recorded: \(model.rawValue) +\(r.inputTokens)in +\(r.outputTokens)out")
    }

    func allRecords() -> [AIRequestRecord] { records }

    func recordsThisMonth() -> [AIRequestRecord] {
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
        return records.filter { $0.timestamp >= start }
    }

    func totalTokensThisMonth() -> (input: Int, output: Int) {
        let monthly = recordsThisMonth()
        return (monthly.reduce(0) { $0 + $1.inputTokens }, monthly.reduce(0) { $0 + $1.outputTokens })
    }

    // MARK: - Persistence

    private func persist() {
        guard let url = storageURL else { return }
        let data = try? JSONEncoder().encode(records)
        try? data?.write(to: url, options: .atomic)
    }

    private func load() -> [AIRequestRecord] {
        guard let url = storageURL,
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([AIRequestRecord].self, from: data)) ?? []
    }
}
