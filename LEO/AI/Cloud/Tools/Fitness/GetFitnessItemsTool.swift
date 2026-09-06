import Foundation

/// Port of `get_fitness_items` (apps/web/src/ai/tools/fitnessTools.ts) — a
/// web-only addition ported back to native. get_today/get_week only cover a
/// narrow forward date window, so an untimed or far-future workout/meal was
/// invisible to the AI — caught live on web: asked to "remove all workout and
/// meal items not marked as done," the AI reported none existed, because no
/// tool could see them, not because there were none.
struct GetFitnessItemsTool: LEOTool {
    struct Input: Decodable, Sendable {}
    struct Output: Encodable, Sendable {
        let items: [FitnessItemSummary]
    }
    struct FitnessItemSummary: Encodable, Sendable {
        let id: String
        let kind: String    // "workout" | "meal"
        let title: String
        let completed: Bool
        let when: String?   // ISO8601, or nil if untimed
    }

    let definition = ToolDefinition(
        name: "get_fitness_items",
        description: "Get EVERY workout and meal item, regardless of date or completion status — including untimed ones and ones outside the next 7 days. get_today/get_week only cover a narrow scheduled window, so use this instead whenever asked about workout/meal plans broadly (e.g. 'remove all my unfinished workouts', 'what meals do I have planned'), not just this week's.",
        inputSchema: ["type": .string("object"), "properties": .object([:]), "required": .array([])]
    )

    func run(_ input: Input, context: ToolContext) async throws -> Output {
        let iso = ISO8601DateFormatter()
        let all = try await context.itemRepository.fetch(predicate: .all)
        let items: [FitnessItemSummary] = all.compactMap { item in
            let kind: String
            if item is WorkoutItem { kind = "workout" }
            else if item is MealItem { kind = "meal" }
            else { return nil }
            return FitnessItemSummary(
                id: item.id.uuidString,
                kind: kind,
                title: item.title,
                completed: item.isCompleted,
                when: item.anchor.sortDate.map { iso.string(from: $0) }
            )
        }
        return Output(items: items)
    }
}
