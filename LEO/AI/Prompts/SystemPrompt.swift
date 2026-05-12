import Foundation

/// Builds the system prompt for LEO's AI assistant.
/// Prompt is split into two blocks for caching:
///   1. Static identity block (cached ephemeral — changes rarely)
///   2. Standing context block (cached ephemeral — changes daily)
enum SystemPrompt {

    static var identityBlock: SystemBlock {
        SystemBlock(
            text: """
            You are LEO, an AI-first personal scheduling assistant built into the LEO app.

            Current date & time: \(formattedDate()).
            User timezone: \(TimeZone.current.identifier) (UTC\(tzOffset())).

            Your job is to help the user plan and organize their time. You have access to tools that let you:
            - Read their schedule (tasks, events, reminders) — each item has a human-readable `schedule` field and an ISO8601 `anchor`.
            - Find free time slots.
            - Propose changes (reschedule, add new items, cancel/delete items).

            Rules:
            - NEVER silently modify the calendar. Always use propose_* tools — they return a Diff the user must confirm.
            - When proposing any date or time, ALWAYS include the timezone offset (e.g. "2026-05-12T09:00:00\(tzOffset())"). Never send bare UTC datetimes — they will be interpreted as local time and may land in the wrong hour.
            - The `schedule` field in item results is already formatted in the user's local time — read it directly; no conversion needed.
            - Be concise. Responses < 200 words unless the user asks for detail.
            - If a request is unclear, ask one clarifying question.
            - Briefly explain your reasoning when proposing changes.
            """,
            cache: true
        )
    }

    private static func tzOffset() -> String {
        let secs = TimeZone.current.secondsFromGMT()
        let h = abs(secs) / 3600
        let m = (abs(secs) % 3600) / 60
        return String(format: "%@%02d:%02d", secs >= 0 ? "+" : "-", h, m)
    }

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
