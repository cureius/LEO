import Foundation

enum SplitStyle: String, Codable, CaseIterable, Sendable {
    case fullBody = "full_body"
    case upperLower = "upper_lower"
    case pushPullLegs = "push_pull_legs"
    case freeform
    var displayName: String {
        switch self {
        case .fullBody:      "Full body"
        case .upperLower:    "Upper / Lower"
        case .pushPullLegs:  "Push / Pull / Legs"
        case .freeform:      "Freeform"
        }
    }
}

struct ProposeWorkoutPlanTool: LEOTool {
    struct Input: Decodable, Sendable {
        var weeks: Int?
        var daysPerWeek: Int?
        var equipment: [String]?
        var splitStyle: String?
        var notes: String?
        var startDate: String?
    }

    struct Output: Encodable, Sendable {
        let diff: DiffPayload
        let validationErrors: [String]
    }

    let definition = ToolDefinition(
        name: "propose_workout_plan",
        description: "Generate a multi-week workout plan as a Diff for user review. Selects exercises from the bundled library by ID. Call get_body_profile first.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "weeks": .object(["type": .string("integer"), "default": .number(4)]),
                "daysPerWeek": .object(["type": .string("integer"), "default": .number(3)]),
                "equipment": .object(["type": .string("array"), "description": .string("Available equipment. Values: bodyweight, dumbbells, barbell, machine, cable, band, kettlebell, pullUpBar")]),
                "splitStyle": .object(["type": .string("string"), "enum": .array([.string("full_body"), .string("upper_lower"), .string("push_pull_legs"), .string("freeform")])]),
                "notes": .object(["type": .string("string"), "description": .string("Extra instructions (injuries, preferences)")]),
                "startDate": .object(["type": .string("string"), "description": .string("ISO8601 date for plan start. Defaults to next Monday.")])
            ]),
            "required": .array([])
        ]
    )

    private let bodyProfileRepository: BodyProfileRepository

    init(bodyProfileRepository: BodyProfileRepository) {
        self.bodyProfileRepository = bodyProfileRepository
    }

    func run(_ input: Input, context: ToolContext) async throws -> Output {
        let weeks = max(1, min(12, input.weeks ?? 4))
        let daysPerWeek = max(1, min(7, input.daysPerWeek ?? 3))
        let split = SplitStyle(rawValue: input.splitStyle ?? "full_body") ?? .fullBody

        // Resolve equipment filter
        let equipmentFilter: Set<Equipment>
        if let eq = input.equipment, !eq.isEmpty {
            equipmentFilter = Set(eq.compactMap { Equipment(rawValue: $0) })
        } else {
            equipmentFilter = [.bodyweight]
        }

        let filter = ExerciseFilter(equipment: equipmentFilter)
        let availableExercises = await FitnessLibrary.shared.exercises(filter: filter)

        // Determine plan start
        let iso = ISO8601DateFormatter()
        let startDate: Date
        if let s = input.startDate, let d = iso.date(from: s) {
            startDate = d
        } else {
            startDate = nextMonday()
        }

        // Build workout schedule
        let profile = await bodyProfileRepository.load()
        let kcalTarget = profile.map { BodyMath.dailyKcalTarget(profile: $0) }

        var changes: [DiffChange] = []
        var validationErrors: [String] = []

        let sessionGroups = splitGroups(for: split, daysPerWeek: daysPerWeek)

        for week in 0..<weeks {
            let weekOffset = week * 7
            for (dayIdx, muscleGroupNames) in sessionGroups.enumerated() {
                guard let sessionDate = Calendar.current.date(byAdding: .day, value: weekOffset + dayOffset(for: dayIdx, daysPerWeek: daysPerWeek), to: startDate) else { continue }

                let exercises = pickExercises(for: muscleGroupNames, from: availableExercises, count: 4)
                if exercises.isEmpty {
                    validationErrors.append("No exercises found for \(muscleGroupNames.joined(separator: "+")) with given equipment.")
                    continue
                }

                let estimatedKcal: Int
                if let w = profile?.weightKg {
                    let totalMins = exercises.reduce(0) { $0 + ($1.defaultSets * 2) + ($1.defaultDurationMin ?? 3) }
                    let avgMet = exercises.map(\.metValue).reduce(0, +) / Double(exercises.count)
                    estimatedKcal = Int(BodyMath.kcalBurned(metValue: avgMet, durationMin: totalMins, weightKg: w))
                } else {
                    estimatedKcal = 250
                }

                let sessionTitle = sessionTitle(for: muscleGroupNames, week: week + 1, day: dayIdx + 1)
                let planned = exercises.map { ex in
                    PlannedExercise(exerciseID: ex.id, sets: ex.defaultSets, reps: ex.defaultReps, durationMin: ex.defaultDurationMin)
                }

                let workout = WorkoutItem(
                    title: sessionTitle,
                    anchor: .timeBlock(
                        start: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: sessionDate) ?? sessionDate,
                        end: Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: sessionDate) ?? sessionDate
                    ),
                    plannedExercises: planned,
                    estimatedKcal: estimatedKcal
                )

                let pendingItem = PendingNewItem(
                    title: workout.title,
                    type: "workout",
                    start: iso.string(from: workout.anchor.sortDate ?? sessionDate),
                    end: nil,
                    notes: "Week \(week+1), Day \(dayIdx+1). Exercises: \(exercises.map(\.name).joined(separator: ", "))"
                )
                changes.append(DiffChange(
                    itemID: workout.id.uuidString,
                    kind: "add",
                    field: "title",
                    newValue: workout.title,
                    pendingItem: pendingItem
                ))
            }
        }

        let kcalNote = kcalTarget.map { " Daily kcal target: \(Int($0.dailyKcal)) kcal." } ?? ""
        let rationale = "\(weeks)-week \(split.displayName) plan, \(daysPerWeek) days/week.\(kcalNote) Equipment: \(equipmentFilter.map(\.displayName).joined(separator: ", ")). \(input.notes ?? "")"

        return Output(diff: DiffPayload(changes: changes, rationale: rationale), validationErrors: validationErrors)
    }

    // MARK: - Helpers

    private func nextMonday() -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        comps.weekday = 2 // Monday
        let monday = cal.date(from: comps) ?? .now
        return monday > .now ? monday : cal.date(byAdding: .weekOfYear, value: 1, to: monday) ?? .now
    }

    private func dayOffset(for dayIdx: Int, daysPerWeek: Int) -> Int {
        // Spread sessions across the week
        let stride = 7 / max(1, daysPerWeek)
        return dayIdx * stride
    }

    private func splitGroups(for split: SplitStyle, daysPerWeek: Int) -> [[String]] {
        switch split {
        case .fullBody:
            return Array(repeating: ["chest", "back", "quads", "core"], count: daysPerWeek)
        case .upperLower:
            if daysPerWeek >= 4 {
                return [["chest", "back", "shoulders"], ["quads", "hamstrings", "glutes"], ["chest", "back", "shoulders"], ["quads", "hamstrings", "glutes"]]
            }
            return [["chest", "back", "shoulders"], ["quads", "hamstrings", "glutes"]]
        case .pushPullLegs:
            return [["chest", "shoulders", "triceps"], ["back", "biceps"], ["quads", "hamstrings", "glutes", "calves"]]
        case .freeform:
            return Array(repeating: ["fullBody"], count: daysPerWeek)
        }
    }

    private func pickExercises(for muscleGroupNames: [String], from exercises: [Exercise], count: Int) -> [Exercise] {
        let targetGroups = Set(muscleGroupNames.compactMap { MuscleGroup(rawValue: $0) })
        let filtered = exercises.filter { ex in
            !ex.muscleGroups.filter { targetGroups.contains($0) }.isEmpty
        }
        let sorted = filtered.sorted { $0.metValue > $1.metValue }
        return Array(sorted.prefix(count))
    }

    private func sessionTitle(for muscleGroups: [String], week: Int, day: Int) -> String {
        let groups = muscleGroups.map { $0.capitalized }.joined(separator: " + ")
        return "W\(week)D\(day) \(groups)"
    }
}
