import Foundation

/// A structured proposal from the AI to modify the user's item graph.
/// The user reviews and accepts/rejects individual changes; changes are never applied silently.
public struct Diff: Hashable, Sendable {
    public let id: UUID
    public let changes: [ItemChange]
    /// Human-readable explanation of why these changes are proposed.
    public let rationale: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        changes: [ItemChange],
        rationale: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.changes = changes
        self.rationale = rationale
        self.createdAt = createdAt
    }

    public var isEmpty: Bool { changes.isEmpty }
    public var addCount: Int { changes.filter { if case .add = $0 { return true }; return false }.count }
    public var updateCount: Int { changes.filter { if case .update = $0 { return true }; return false }.count }
    public var deleteCount: Int { changes.filter { if case .delete = $0 { return true }; return false }.count }
}
