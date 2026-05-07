import Foundation

/// Composite parser: deterministic first; Foundation Models (M1-T05) when confidence < 0.8.
/// Stub implementation — FM integration wired after Apple Intelligence APIs confirmed available.
public struct CompositeParser: QuickAddParser, Sendable {
    private let deterministic = DeterministicParser()
    /// Confidence threshold below which a second-pass parser is invoked.
    private let escalationThreshold: Double

    public init(escalationThreshold: Double = 0.8) {
        self.escalationThreshold = escalationThreshold
    }

    public func parse(_ text: String) async -> ParseResult {
        let result = await deterministic.parse(text)
        // Foundation Models fallback stub — plugged in during M1-T05 when FM API is available.
        // For now: return deterministic result regardless of confidence.
        return result
    }
}
