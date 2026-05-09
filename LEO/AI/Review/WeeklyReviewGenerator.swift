import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "weekly-review")

// MARK: - Weekly review model

public struct WeeklyReview: Codable, Sendable, Identifiable {
    public let id: UUID
    public let weekInterval: DateInterval
    public let generatedAt: Date

    public var completedCount: Int
    public var slippedCount: Int
    public var habitStreakSummaries: [HabitStreakSummary]

    // AI-generated narrative sections
    public var highlights: String
    public var slips: String
    public var themes: String
    public var suggestions: [String]

    public struct HabitStreakSummary: Codable, Sendable {
        public let habitName: String
        public let streakDays: Int
        public let completedThisWeek: Int
        public let totalThisWeek: Int
    }
}

extension DateInterval: Codable {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(start)
        try c.encode(end)
    }
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let start = try c.decode(Date.self)
        let end = try c.decode(Date.self)
        self.init(start: start, end: end)
    }
}

// MARK: - Generator

actor WeeklyReviewGenerator {
    private let itemRepository: ItemRepository
    private let habitRepository: HabitRepository
    private let claudeClient: ClaudeClient

    init(itemRepository: ItemRepository, habitRepository: HabitRepository, claudeClient: ClaudeClient) {
        self.itemRepository = itemRepository
        self.habitRepository = habitRepository
        self.claudeClient = claudeClient
    }

    func generate(for week: DateInterval) async throws -> WeeklyReview {
        let items = try await itemRepository.fetch(predicate: .inDateInterval(week))
        let habits = try await habitRepository.fetchAll()
        let allInstances = try await habitRepository.fetchInstances(in: week)

        let completed = items.filter(\.isCompleted).count
        let slipped = items.filter { !$0.isCompleted && $0.isOverdue }.count

        let habitSummaries: [WeeklyReview.HabitStreakSummary] = habits.map { habit in
            let instances = allInstances.filter { $0.habitID == habit.id }
            let streak = StreakEngine.currentStreak(for: habit, instances: instances)
            let weekInstances = instances.filter { inst -> Bool in
                guard let d = inst.anchor.sortDate else { return false }
                return week.contains(d)
            }
            return WeeklyReview.HabitStreakSummary(
                habitName: habit.name,
                streakDays: streak.activeStreakDays,
                completedThisWeek: weekInstances.filter(\.isCompleted).count,
                totalThisWeek: weekInstances.count
            )
        }

        // Build AI narrative
        let prompt = buildPrompt(items: items, habits: habitSummaries, completed: completed, slipped: slipped)
        let narrative = try await generateNarrative(prompt: prompt)

        return WeeklyReview(
            id: UUID(),
            weekInterval: week,
            generatedAt: .now,
            completedCount: completed,
            slippedCount: slipped,
            habitStreakSummaries: habitSummaries,
            highlights: narrative.highlights,
            slips: narrative.slips,
            themes: narrative.themes,
            suggestions: narrative.suggestions
        )
    }

    // MARK: - Private

    private func buildPrompt(
        items: [any Item],
        habits: [WeeklyReview.HabitStreakSummary],
        completed: Int,
        slipped: Int
    ) -> String {
        let habitLines = habits.map { "\($0.habitName): \($0.completedThisWeek)/\($0.totalThisWeek) done, \($0.streakDays) day streak" }
        return """
        Generate a weekly review for a productivity app.

        Stats:
        - Completed items: \(completed)
        - Slipped (overdue) items: \(slipped)
        - Habits this week: \(habitLines.joined(separator: "; "))

        Return a JSON object with these fields:
        {"highlights": "...", "slips": "...", "themes": "...", "suggestions": ["...", "...", "..."]}

        Keep each field under 100 words. Suggestions should be specific and actionable.
        """
    }

    private struct NarrativeResponse: Decodable {
        let highlights: String
        let slips: String
        let themes: String
        let suggestions: [String]
    }

    private func generateNarrative(prompt: String) async throws -> NarrativeResponse {
        let response = try await claudeClient.send(
            messages: [Message.user(prompt)],
            system: [SystemBlock(text: "You are a personal productivity coach. Be concise and encouraging.")]
        )

        let text = response.content.compactMap { block -> String? in
            if case .text(let t) = block { return t.text }
            return nil
        }.joined()

        // Extract JSON from the response
        if let jsonStart = text.firstIndex(of: "{"),
           let jsonEnd = text.lastIndex(of: "}") {
            let jsonStr = String(text[jsonStart...jsonEnd])
            if let data = jsonStr.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(NarrativeResponse.self, from: data) {
                return parsed
            }
        }

        // Fallback if AI doesn't return valid JSON
        return NarrativeResponse(
            highlights: "You completed \(text.isEmpty ? "several" : "") items this week.",
            slips: "Some items slipped past their deadlines.",
            themes: "Focus on consistency next week.",
            suggestions: ["Review your priorities", "Schedule deep work blocks", "Check in on habit streaks"]
        )
    }
}
