import AppIntents
import Foundation

// MARK: - Focus Filter State

/// Holds the currently active Focus filter configuration.
/// Views read this actor to decide which items to hide.
actor FocusFilterState {
    static let shared = FocusFilterState()

    private(set) var hiddenTagNames: Set<String> = []
    private(set) var isActive: Bool = false

    func update(hiddenTagNames: Set<String>) {
        self.hiddenTagNames = hiddenTagNames
        self.isActive = !hiddenTagNames.isEmpty
    }

    func reset() {
        hiddenTagNames = []
        isActive = false
    }
}

// MARK: - Focus Filter Intent

/// Conforms to SetFocusFilterIntent — iOS applies this filter when the named Focus is active.
struct LEOFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "LEO Focus Filter"
    static var description: IntentDescription? = IntentDescription(
        "Configure which LEO items appear during this Focus mode."
    )

    var displayRepresentation: DisplayRepresentation {
        let tagList = hiddenTagNames?.joined(separator: ", ") ?? "none"
        return DisplayRepresentation(title: "LEO Focus Filter", subtitle: "Hiding: \(tagList)")
    }

    @Parameter(title: "Hide items tagged with")
    var hiddenTagNames: [String]?

    func perform() async throws -> some IntentResult {
        let tags = Set(hiddenTagNames ?? [])
        await FocusFilterState.shared.update(hiddenTagNames: tags)
        return .result()
    }
}
