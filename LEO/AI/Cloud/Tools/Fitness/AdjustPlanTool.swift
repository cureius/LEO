import Foundation

struct AdjustPlanTool: LEOTool {
    struct Input: Decodable, Sendable {
        let affectedItemIDs: [String]
        let instruction: String
        var rationale: String?
    }

    struct Output: Encodable, Sendable {
        let diff: DiffPayload
    }

    let definition = ToolDefinition(
        name: "adjust_plan",
        description: "Adjust an existing workout or meal plan by updating, swapping, or removing specific items. The model should describe what changes to make in the instruction field and include the affected item IDs.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "affectedItemIDs": .object(["type": .string("array"), "description": .string("UUIDs of items to modify")]),
                "instruction": .object(["type": .string("string"), "description": .string("What to change, e.g. 'swap leg day for cardio' or 'reduce sets by 1'")]),
                "rationale": .object(["type": .string("string")])
            ]),
            "required": .array([.string("affectedItemIDs"), .string("instruction")])
        ]
    )

    func run(_ input: Input, context: ToolContext) async throws -> Output {
        var changes: [DiffChange] = []

        let lower = input.instruction.lowercased()
        let isDelete = lower.contains("remove") || lower.contains("delete") || lower.contains("cancel") || lower.contains("skip")

        for idStr in input.affectedItemIDs {
            guard let uuid = UUID(uuidString: idStr) else { continue }
            let items = try await context.itemRepository.fetch(predicate: .byID(uuid))
            guard let item = items.first else { continue }

            if isDelete {
                changes.append(DiffChange(itemID: idStr, kind: "delete", field: "", newValue: ""))
            } else if lower.contains("swap") || lower.contains("replace") {
                // For swap, mark as update + note
                changes.append(DiffChange(
                    itemID: idStr,
                    kind: "update",
                    field: "notes",
                    newValue: "Adjusted: \(input.instruction)"
                ))
            } else {
                // Generic update
                changes.append(DiffChange(
                    itemID: idStr,
                    kind: "update",
                    field: "notes",
                    newValue: item.notes.map { $0 + " | Adjusted: \(input.instruction)" } ?? "Adjusted: \(input.instruction)"
                ))
            }
        }

        let rationale = input.rationale ?? "Adjusted \(input.affectedItemIDs.count) item(s): \(input.instruction)"
        return Output(diff: DiffPayload(changes: changes, rationale: rationale))
    }
}
