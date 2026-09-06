import Foundation

/// Port of `set_workout_exercises` (apps/web/src/ai/tools/fitnessTools.ts) — a
/// web-only addition ported back to native. `AdjustPlanTool` can only ever
/// write a free-text `notes` field, so an instruction like "Day 1 is Bench,
/// Incline DB press, OHP..." on an EXISTING workout landed as a text blob
/// instead of individually trackable exercise rows. `propose_workout_plan`
/// already builds real `plannedExercises` for brand-new workouts (see
/// ProposeWorkoutPlanTool + PendingNewItem.exercises); this is the equivalent
/// for editing an existing one.
struct SetWorkoutExercisesTool: LEOTool {
    struct Input: Decodable, Sendable {
        struct ExerciseInput: Decodable, Sendable {
            let name: String
            let sets: Int
            let reps: Int
            var weightKg: Double?
        }
        let itemID: String
        let exercises: [ExerciseInput]
        var estimatedKcal: Int?
        let rationale: String
    }
    struct Output: Encodable, Sendable {
        var diff: DiffPayload?
        var error: String?
    }

    let definition = ToolDefinition(
        name: "set_workout_exercises",
        description: "Set the exact exercises (name, sets, reps, optional weight) on an existing workout item, so they show up as individually trackable rows — not just a text note. Use this whenever the user gives (or you're deriving from an attached plan/photo) specific exercises with sets/reps for a workout that already exists; use adjust_plan instead only for non-exercise changes. Returns a Diff for user review.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "itemID": .object(["type": .string("string"), "description": .string("The workout item to update — get this from get_fitness_items/get_today/get_week.")]),
                "exercises": .object(["type": .string("array")]),
                "estimatedKcal": .object(["type": .string("integer"), "description": .string("Optional estimated calories burned for the whole session")]),
                "rationale": .object(["type": .string("string")])
            ]),
            "required": .array([.string("itemID"), .string("exercises"), .string("rationale")])
        ]
    )

    func run(_ input: Input, context: ToolContext) async throws -> Output {
        guard let uuid = UUID(uuidString: input.itemID) else {
            return Output(diff: nil, error: "Invalid item id \(input.itemID)")
        }
        let fetched = try await context.itemRepository.fetch(predicate: .byID(uuid))
        guard let item = fetched.first else {
            return Output(diff: nil, error: "No item with id \(input.itemID)")
        }
        guard item is WorkoutItem else {
            return Output(diff: nil, error: "Item \(input.itemID) is not a workout — set_workout_exercises only applies to workout items")
        }

        let exercises = input.exercises.map { e in
            PlannedExercise(exerciseID: e.name, sets: e.sets, reps: e.reps, weightKg: e.weightKg)
        }
        // Same encode-a-JSON-blob-into-newValue shape web's set_workout_exercises
        // uses for its "workoutDetail" field — keeps this as a single DiffChange
        // (not two) so accept/reject state in the review sheet can't collide.
        struct WorkoutDetail: Encodable { let exercises: [PlannedExercise]; let estimatedKcal: Int? }
        let detail = WorkoutDetail(exercises: exercises, estimatedKcal: input.estimatedKcal)
        guard let data = try? JSONEncoder().encode(detail), let json = String(data: data, encoding: .utf8) else {
            return Output(diff: nil, error: "Failed to encode exercise data")
        }

        let change = DiffChange(itemID: input.itemID, kind: "update", field: "workoutDetail", newValue: json)
        return Output(diff: DiffPayload(changes: [change], rationale: input.rationale), error: nil)
    }
}
