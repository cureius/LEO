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
            let start: String?
            let end: String?
        }
        let items: [NewItem]
        let rationale: String
    }
    struct Output: Encodable, Sendable { let diff: DiffPayload }

    let definition = ToolDefinition(
        name: "propose_add",
        description: "Propose adding one or more new items. Returns a Diff for user review — does NOT create items.",
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
        let changes = input.items.map { item in
            DiffChange(itemID: UUID().uuidString, kind: "add", field: "title", newValue: item.title)
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
        let changes = input.ids.map { id in
            DiffChange(itemID: id, kind: "delete", field: "", newValue: "")
        }
        return Output(diff: DiffPayload(changes: changes, rationale: input.rationale))
    }
}

// MARK: - Diff payload (tool output)

struct DiffPayload: Codable, Sendable {
    let changes: [DiffChange]
    let rationale: String
}

struct DiffChange: Codable, Sendable {
    let itemID: String
    let kind: String   // "add", "update", "delete"
    let field: String
    let newValue: String
}
