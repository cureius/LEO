import Foundation

// MARK: - ProposeRescheduleTool

struct ProposeRescheduleTool: LEOTool {
    struct Input: Decodable, Sendable {
        struct RescheduleItem: Decodable, Sendable {
            let id: String
            let newStart: String        // ISO8601
            let newEnd: String?         // ISO8601; nil for non-blocks
        }
        let items: [RescheduleItem]
        let rationale: String
    }
    struct Output: Encodable, Sendable { let diff: DiffPayload }

    let definition = ToolDefinition(
        name: "propose_reschedule",
        description: "Propose rescheduling one or more items. Returns a Diff for user review — does NOT apply changes.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "items": .object(["type": .string("array")]),
                "rationale": .object(["type": .string("string")])
            ]),
            "required": .array([.string("items"), .string("rationale")])
        ]
    )

    func run(_ input: Input, context: ToolContext) async throws -> Output {
        let iso = ISO8601DateFormatter()
        var changes: [DiffChange] = []
        for r in input.items {
            guard let uuid = UUID(uuidString: r.id),
                  let newStart = iso.date(from: r.newStart) else { continue }
            let newEnd = r.newEnd.flatMap { iso.date(from: $0) }
            let newAnchor = newEnd != nil ? "timeBlock:\(r.newStart)–\(r.newEnd!)" : "point:\(r.newStart)"
            changes.append(DiffChange(itemID: uuid.uuidString, kind: "update", field: "anchor", newValue: newAnchor))
        }
        return Output(diff: DiffPayload(changes: changes, rationale: input.rationale))
    }
}

// MARK: - ProposeAddTool

struct ProposeAddTool: LEOTool {
    struct Input: Decodable, Sendable {
        struct NewItem: Decodable, Sendable {
            let title: String
            let type: String            // "task", "event", "reminder"
            let start: String?          // ISO8601 datetime
            let end: String?            // ISO8601 datetime (for events/blocks)
            let notes: String?
        }
        let items: [NewItem]
        let rationale: String
    }
    struct Output: Encodable, Sendable { let diff: DiffPayload }

    let definition = ToolDefinition(
        name: "propose_add",
        description: "Propose adding one or more new tasks, events, or reminders. Returns a Diff for user review — does NOT create items immediately.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "items": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "title": .object(["type": .string("string")]),
                            "type": .object([
                                "type": .string("string"),
                                "enum": .array([.string("task"), .string("event"), .string("reminder")])
                            ]),
                            "start": .object(["type": .string("string"), "description": .string("ISO8601 datetime WITH timezone offset, e.g. 2026-05-10T09:00:00+05:30. Never omit the offset.")]),
                            "end":   .object(["type": .string("string"), "description": .string("ISO8601 datetime WITH timezone offset for block/event end.")]),
                            "notes": .object(["type": .string("string")])
                        ]),
                        "required": .array([.string("title"), .string("type")])
                    ])
                ]),
                "rationale": .object(["type": .string("string")])
            ]),
            "required": .array([.string("items"), .string("rationale")])
        ]
    )

    func run(_ input: Input, context: ToolContext) async throws -> Output {
        let changes = input.items.map { item in
            DiffChange(
                itemID: UUID().uuidString,
                kind: "add",
                field: "title",
                newValue: item.title,
                pendingItem: PendingNewItem(
                    title: item.title,
                    type: item.type,
                    start: item.start,
                    end: item.end,
                    notes: item.notes
                )
            )
        }
        return Output(diff: DiffPayload(changes: changes, rationale: input.rationale))
    }
}

// MARK: - ProposeCancelTool

struct ProposeCancelTool: LEOTool {
    struct Input: Decodable, Sendable {
        let ids: [String]
        let rationale: String
    }
    struct Output: Encodable, Sendable { let diff: DiffPayload }

    let definition = ToolDefinition(
        name: "propose_cancel",
        description: "Propose deleting or cancelling items. Returns a Diff for user review.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "ids": .object(["type": .string("array")]),
                "rationale": .object(["type": .string("string")])
            ]),
            "required": .array([.string("ids"), .string("rationale")])
        ]
    )

    func run(_ input: Input, context: ToolContext) async throws -> Output {
        var changes: [DiffChange] = []
        for idStr in input.ids {
            // Look up the item so we can show its real title in the review sheet.
            let title: String
            if let uuid = UUID(uuidString: idStr),
               let item = (try? await context.itemRepository.fetch(predicate: .byID(uuid)))?.first {
                title = item.title
            } else {
                title = "Unknown item"
            }
            changes.append(DiffChange(itemID: idStr, kind: "delete", field: "title", newValue: title))
        }
        return Output(diff: DiffPayload(changes: changes, rationale: input.rationale))
    }
}

// MARK: - Diff payload (tool output)

struct DiffPayload: Codable, Hashable, Sendable {
    let changes: [DiffChange]
    let rationale: String
}

struct DiffChange: Codable, Hashable, Sendable {
    let itemID: String
    let kind: String        // "add", "update", "delete"
    let field: String
    let newValue: String
    var pendingItem: PendingNewItem?  // only for kind == "add"
}

/// Full data needed to create a new item when the user confirms an "add" diff.
struct PendingNewItem: Codable, Hashable, Sendable {
    let title: String
    let type: String    // "task", "event", "reminder", "workout", "meal"
    let start: String?  // ISO8601
    let end: String?    // ISO8601
    let notes: String?
    /// Structured exercise data for `type == "workout"`. Without this, a workout
    /// diff could only carry its exercises as a flattened notes string — the
    /// applied item ended up with an empty `plannedExercises` array and nothing
    /// individually trackable, even though the tool that built the diff (e.g.
    /// ProposeWorkoutPlanTool) had already computed the real structured data.
    var exercises: [PlannedExercise]? = nil
    var estimatedKcal: Int? = nil
}
