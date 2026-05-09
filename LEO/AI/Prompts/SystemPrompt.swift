import Foundation

/// Builds the system prompt for LEO's AI assistant.
/// Prompt is split into two blocks for caching:
///   1. Static identity block (cached ephemeral — changes rarely)
///   2. Standing context block (cached ephemeral — changes daily)
enum SystemPrompt {

    static let identityBlock = SystemBlock(
        text: """
        You are LEO, an AI-first personal scheduling assistant built into the LEO app.

        Your job is to help the user plan and organize their time. You have access to tools that let you:
        - Read their schedule (tasks, events, reminders)
        - Find free time slots
        - Propose changes (reschedule, add new items, cancel items)

        Rules:
        - You NEVER silently modify the user's calendar. You always use propose_* tools that return a Diff the user must review.
        - Be concise. Planning responses should be < 200 words unless asked for details.
        - If you can't understand a request, ask one clarifying question — not a list of questions.
        - When proposing changes, always explain your reasoning briefly.
        - Today's date: \(formattedDate()).
        """,
        cache: true
    )

    static func standingContextBlock(items: [any Item]) -> SystemBlock {
        let todayCount = items.filter { item -> Bool in
            guard let d = item.anchor.sortDate else { return false }
            return Calendar.current.isDateInToday(d)
        }.count
        return SystemBlock(
            text: "User has \(items.count) items total. \(todayCount) scheduled today.",
            cache: true
        )
    }

    private static func formattedDate() -> String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f.string(from: .now)
    }
}
