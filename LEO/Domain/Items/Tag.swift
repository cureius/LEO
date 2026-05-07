import Foundation

public struct Tag: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let color: TagColor

    public init(id: UUID = UUID(), name: String, color: TagColor = .blue) {
        self.id = id
        self.name = name
        self.color = color
    }
}

/// Named color palette for tags; no free-form hex in v1.
public enum TagColor: String, Hashable, Sendable, Codable, CaseIterable {
    case red, orange, yellow, green, teal, blue, indigo, purple, pink, gray

    var displayName: String { rawValue.capitalized }
}
