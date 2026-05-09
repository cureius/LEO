import AppIntents
import Foundation

// MARK: - CreateItemIntent

struct CreateItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to LEO"
    static let description = IntentDescription("Creates a new item in LEO.")
    static let openAppWhenRun = false

    @Parameter(title: "Item text")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await DeterministicParser().parse(text)
        let item: any Item = result.draft ?? TaskItem(title: text.isEmpty ? "New item" : text, anchor: .untimed)
        try await SharedRepository.shared.add(item)
        return .result(dialog: "Added '\(item.title)' to LEO.")
    }
}

// MARK: - CompleteItemIntent

struct CompleteItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete in LEO"
    static let description = IntentDescription("Marks a LEO item as complete.")
    static let openAppWhenRun = false

    @Parameter(title: "Item")
    var item: LEOItemEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let items = try await SharedRepository.shared.fetch(predicate: .byID(item.id))
        guard var found = items.first else {
            throw $item.needsValueError("Could not find that item.")
        }
        found.completion = .completed(at: .now)
        try await SharedRepository.shared.update(found)
        return .result(dialog: "Completed '\(item.title)' in LEO.")
    }
}

// MARK: - GetTodayIntent

struct GetTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's summary"
    static let description = IntentDescription("Returns a summary of today's LEO items.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let today = Date.now
        let start = Calendar.current.startOfDay(for: today)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? today
        let interval = DateInterval(start: start, end: end)
        let items = try await SharedRepository.shared.fetch(predicate: .inDateInterval(interval))
        let open = items.filter { !$0.isCompleted }
        let done = items.filter(\.isCompleted)

        if open.isEmpty && done.isEmpty {
            return .result(dialog: "You have nothing scheduled for today in LEO.")
        }

        var summary = "You have \(open.count) item\(open.count == 1 ? "" : "s") today."
        if let first = open.first {
            summary += " First up: \(first.title)."
        }
        if done.count > 0 {
            summary += " \(done.count) already done."
        }
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}

// MARK: - App Shortcuts

struct LEOAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateItemIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "Create in \(.applicationName)",
                "Capture in \(.applicationName)"
            ],
            shortTitle: "Add to LEO",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: CompleteItemIntent(),
            phrases: [
                "Complete \(\.$item) in \(.applicationName)",
                "Mark \(\.$item) done in \(.applicationName)"
            ],
            shortTitle: "Complete in LEO",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: GetTodayIntent(),
            phrases: [
                "What's on my \(.applicationName) today",
                "Show my \(.applicationName) schedule",
                "What do I have in \(.applicationName) today"
            ],
            shortTitle: "Today's summary",
            systemImageName: "calendar"
        )
    }
}
