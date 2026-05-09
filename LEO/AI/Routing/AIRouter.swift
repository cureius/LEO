import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "ai-router")

// MARK: - Router

/// Picks the cheapest model that can handle a given request.
/// Decision tree based on prompt length + expected tool-call count.
actor AIRouter {
    static let shared = AIRouter()

    // Manual override persisted in UserDefaults
    enum Override: String {
        case none = "none"
        case alwaysOpus = "always_opus"
        case preferOnDevice = "prefer_on_device"
    }

    var routingOverride: Override {
        Override(rawValue: UserDefaults.standard.string(forKey: "ai_routing_override") ?? "none") ?? .none
    }

    func setOverride(_ override: Override) {
        UserDefaults.standard.set(override.rawValue, forKey: "ai_routing_override")
    }

    // MARK: - Route

    /// Choose which model to use for a given prompt context.
    func route(prompt: String, expectedToolCalls: Int = 0, userExplicitlyQuick: Bool = false) -> ClaudeModel {
        // Override check
        switch routingOverride {
        case .alwaysOpus: return .opus47
        case .preferOnDevice: return .haiku45  // closest to on-device in v1
        case .none: break
        }

        // User said "quick" → Haiku
        if userExplicitlyQuick { return .haiku45 }

        // Long multi-step planning → Opus
        if expectedToolCalls >= 4 || prompt.count > 2000 { return .opus47 }

        // Single-step → Sonnet
        if expectedToolCalls >= 1 { return .sonnet46 }

        // Simple summarize/parse → Haiku
        return .haiku45
    }

    func logRoute(prompt: String, model: ClaudeModel, reason: String) {
        logger.debug("Route: \(model.rawValue) — \(reason) — prompt=\(prompt.prefix(60))…")
    }
}
