import Foundation

/// A single atomic change the AI proposes to the user's item graph.
public enum ItemChange: Hashable, Sendable {
    case add(AnyItemBox)
    case update(id: UUID, patch: ItemPatch)
    case delete(id: UUID)
}

/// Type-erased box so ItemChange can hold `any Item` and still conform to Hashable/Sendable.
public struct AnyItemBox: Hashable, Sendable {
    private let _id: UUID
    private let _hashValue: Int
    // Not possible to store `any Item` and be Hashable without a workaround.
    // Store the id + description; the full item is only needed at review time.
    public let id: UUID
    public let itemTypeDescription: String

    // In practice, DiffReviewSheet holds the full typed items separately.
    // This box carries identity for Diff hashing purposes.
    public init(id: UUID, typeDescription: String) {
        self.id = id
        self._id = id
        self.itemTypeDescription = typeDescription
        self._hashValue = id.hashValue
    }

    public static func == (lhs: AnyItemBox, rhs: AnyItemBox) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
