import Foundation

/// A partial update to an Item — only fields set in the patch are applied.
public struct ItemPatch: Hashable, Sendable {
    public var title: String?
    public var notes: String??   // Double optional: nil = no change; .some(nil) = clear the field
    public var importance: Importance?
    public var anchor: Anchor?
    public var completion: Completion?
    public var tags: [Tag]?

    public init(
        title: String? = nil,
        notes: String?? = nil,
        importance: Importance? = nil,
        anchor: Anchor? = nil,
        completion: Completion? = nil,
        tags: [Tag]? = nil
    ) {
        self.title = title
        self.notes = notes
        self.importance = importance
        self.anchor = anchor
        self.completion = completion
        self.tags = tags
    }
}
