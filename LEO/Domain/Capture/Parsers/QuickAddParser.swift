import Foundation

/// The result of parsing a quick-add text entry.
public struct ParseResult: Sendable {
    /// The draft item ready to save. Nil if parsing completely failed.
    public let draft: (any Item)?
    /// Confidence 0–1. < 0.5 = send to Inbox by default.
    public let confidence: Double
    /// Human-readable description of what was understood.
    public let rationale: String

    public init(draft: (any Item)?, confidence: Double, rationale: String) {
        self.draft = draft
        self.confidence = confidence
        self.rationale = rationale
    }

    public var shouldDefaultToInbox: Bool { confidence < 0.5 }
}

/// Parsing state exposed to the quick-add view model.
public enum ParseState: Sendable {
    case idle
    case parsing
    case parsed(ParseResult)
    case failed(String)
}

/// Common interface for all quick-add parsers.
public protocol QuickAddParser: Sendable {
    func parse(_ text: String) async -> ParseResult
}
