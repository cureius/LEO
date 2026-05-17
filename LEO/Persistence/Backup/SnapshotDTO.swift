import Foundation

// MARK: - Root

/// Versioned JSON snapshot of the entire LEO data store.
struct AppSnapshot: Codable {
    static let currentVersion = 1

    let version: Int
    let exportedAt: Date
    let appVersion: String

    var tasks: [SnapshotTask]
    var events: [SnapshotEvent]
    var reminders: [SnapshotReminder]
    var alarms: [SnapshotAlarm]
    var habitInstances: [SnapshotHabitInstance]
    var workouts: [SnapshotWorkout]
    var meals: [SnapshotMeal]
    var habits: [SnapshotHabit]
    var bodyProfile: UserBodyProfile?
    var measurements: [BodyMeasurement]
}

// MARK: - Shared helpers

/// Tags are stored inline per-item; IDs are preserved so cross-item consistency is maintained on restore.
struct SnapshotTag: Codable {
    var id: UUID
    var name: String
    var colorRaw: String
}

extension Tag {
    var snapshot: SnapshotTag { SnapshotTag(id: id, name: name, colorRaw: color.rawValue) }
    static func from(_ s: SnapshotTag) -> Tag {
        Tag(id: s.id, name: s.name, color: TagColor(rawValue: s.colorRaw) ?? .blue)
    }
}

// Anchor and Completion have private Codable wrappers in ItemMapping.
// We reuse their encoded() / decoded() API and store results as base64 strings so
// the snapshot stays valid JSON without duplicating the encoding logic.
private extension Data {
    var base64: String { base64EncodedString() }
}

// MARK: - TaskItem

struct SnapshotTask: Codable {
    var id: UUID
    var title: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var importanceRaw: Int
    var anchorB64: String
    var completionB64: String
    var tags: [SnapshotTag]
    var deadline: Date?
    var estimatedDurationSeconds: Double?
    var rruleRaw: String?

    init(from item: TaskItem) throws {
        id = item.id; title = item.title; notes = item.notes
        createdAt = item.createdAt; updatedAt = item.updatedAt
        importanceRaw = item.importance.rawValue
        anchorB64 = try item.anchor.encoded().base64
        completionB64 = try item.completion.encoded().base64
        tags = item.tags.map(\.snapshot)
        deadline = item.deadline
        estimatedDurationSeconds = item.estimatedDuration.map { Double($0.components.seconds) }
        rruleRaw = item.rruleRaw
    }

    func toItem() throws -> TaskItem {
        TaskItem(
            id: id, title: title, notes: notes,
            createdAt: createdAt, updatedAt: updatedAt,
            importance: Importance(rawValue: importanceRaw) ?? .normal,
            anchor: try decode(anchorB64),
            completion: try decode(completionB64),
            tags: tags.map(Tag.from),
            deadline: deadline,
            estimatedDuration: estimatedDurationSeconds.map { .seconds($0) },
            rruleRaw: rruleRaw
        )
    }
}

// MARK: - EventItem

struct SnapshotEvent: Codable {
    var id: UUID
    var title: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var importanceRaw: Int
    var anchorB64: String
    var completionB64: String
    var tags: [SnapshotTag]
    var location: String?
    var attendees: [String]
    var externalRef: ExternalRef?
    var rruleRaw: String?

    init(from item: EventItem) throws {
        id = item.id; title = item.title; notes = item.notes
        createdAt = item.createdAt; updatedAt = item.updatedAt
        importanceRaw = item.importance.rawValue
        anchorB64 = try item.anchor.encoded().base64
        completionB64 = try item.completion.encoded().base64
        tags = item.tags.map(\.snapshot)
        location = item.location
        attendees = item.attendees
        externalRef = item.externalRef
        rruleRaw = item.rruleRaw
    }

    func toItem() throws -> EventItem {
        EventItem(
            id: id, title: title, notes: notes,
            createdAt: createdAt, updatedAt: updatedAt,
            importance: Importance(rawValue: importanceRaw) ?? .normal,
            anchor: try decode(anchorB64),
            completion: try decode(completionB64),
            tags: tags.map(Tag.from),
            location: location, attendees: attendees,
            externalRef: externalRef, rruleRaw: rruleRaw
        )
    }
}

// MARK: - ReminderItem

struct SnapshotReminder: Codable {
    var id: UUID
    var title: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var importanceRaw: Int
    var anchorB64: String
    var completionB64: String
    var tags: [SnapshotTag]
    var leadTime: TimeInterval?
    var externalRef: ExternalRef?
    var rruleRaw: String?

    init(from item: ReminderItem) throws {
        id = item.id; title = item.title; notes = item.notes
        createdAt = item.createdAt; updatedAt = item.updatedAt
        importanceRaw = item.importance.rawValue
        anchorB64 = try item.anchor.encoded().base64
        completionB64 = try item.completion.encoded().base64
        tags = item.tags.map(\.snapshot)
        leadTime = item.leadTime
        externalRef = item.externalRef
        rruleRaw = item.rruleRaw
    }

    func toItem() throws -> ReminderItem {
        ReminderItem(
            id: id, title: title, notes: notes,
            createdAt: createdAt, updatedAt: updatedAt,
            importance: Importance(rawValue: importanceRaw) ?? .normal,
            anchor: try decode(anchorB64),
            completion: try decode(completionB64),
            tags: tags.map(Tag.from),
            leadTime: leadTime, externalRef: externalRef, rruleRaw: rruleRaw
        )
    }
}

// MARK: - AlarmItem

struct SnapshotAlarm: Codable {
    var id: UUID
    var title: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var importanceRaw: Int
    var anchorB64: String
    var completionB64: String
    var tags: [SnapshotTag]
    var soundProfileRaw: String
    var escalates: Bool
    var rruleRaw: String?

    init(from item: AlarmItem) throws {
        id = item.id; title = item.title; notes = item.notes
        createdAt = item.createdAt; updatedAt = item.updatedAt
        importanceRaw = item.importance.rawValue
        anchorB64 = try item.anchor.encoded().base64
        completionB64 = try item.completion.encoded().base64
        tags = item.tags.map(\.snapshot)
        soundProfileRaw = item.soundProfile.rawValue
        escalates = item.escalates
        rruleRaw = item.rruleRaw
    }

    func toItem() throws -> AlarmItem {
        AlarmItem(
            id: id, title: title, notes: notes,
            createdAt: createdAt, updatedAt: updatedAt,
            importance: Importance(rawValue: importanceRaw) ?? .urgent,
            anchor: try decode(anchorB64),
            completion: try decode(completionB64),
            tags: tags.map(Tag.from),
            soundProfile: AlarmSound(rawValue: soundProfileRaw) ?? .default,
            escalates: escalates, rruleRaw: rruleRaw
        )
    }
}

// MARK: - HabitInstanceItem

struct SnapshotHabitInstance: Codable {
    var id: UUID
    var title: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var importanceRaw: Int
    var anchorB64: String
    var completionB64: String
    var habitID: UUID
    var targetDurationSeconds: Double?

    init(from item: HabitInstanceItem) throws {
        id = item.id; title = item.title; notes = item.notes
        createdAt = item.createdAt; updatedAt = item.updatedAt
        importanceRaw = item.importance.rawValue
        anchorB64 = try item.anchor.encoded().base64
        completionB64 = try item.completion.encoded().base64
        habitID = item.habitID
        targetDurationSeconds = item.targetDuration.map { Double($0.components.seconds) }
    }

    func toItem() throws -> HabitInstanceItem {
        HabitInstanceItem(
            id: id, title: title, notes: notes,
            createdAt: createdAt, updatedAt: updatedAt,
            importance: Importance(rawValue: importanceRaw) ?? .normal,
            anchor: try decode(anchorB64),
            completion: try decode(completionB64),
            habitID: habitID,
            targetDuration: targetDurationSeconds.map { .seconds($0) }
        )
    }
}

// MARK: - WorkoutItem (exercise data stored as base64 JSON)

struct SnapshotWorkout: Codable {
    var id: UUID
    var title: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var importanceRaw: Int
    var anchorB64: String
    var completionB64: String
    var tags: [SnapshotTag]
    var plannedExercisesB64: String
    var estimatedKcal: Int
    var actualKcal: Int?
    var actualExercisesB64: String?
    var healthKitWorkoutID: String?

    init(from item: WorkoutItem) throws {
        id = item.id; title = item.title; notes = item.notes
        createdAt = item.createdAt; updatedAt = item.updatedAt
        importanceRaw = item.importance.rawValue
        anchorB64 = try item.anchor.encoded().base64
        completionB64 = try item.completion.encoded().base64
        tags = item.tags.map(\.snapshot)
        plannedExercisesB64 = ((try? JSONEncoder().encode(item.plannedExercises)) ?? Data()).base64
        estimatedKcal = item.estimatedKcal
        actualKcal = item.actualKcal
        actualExercisesB64 = item.actualExercises.flatMap { try? JSONEncoder().encode($0) }?.base64
        healthKitWorkoutID = item.healthKitWorkoutID
    }

    func toItem() throws -> WorkoutItem {
        let planned = Data(base64Encoded: plannedExercisesB64)
            .flatMap { try? JSONDecoder().decode([PlannedExercise].self, from: $0) } ?? []
        let actual = actualExercisesB64.flatMap { Data(base64Encoded: $0) }
            .flatMap { try? JSONDecoder().decode([LoggedExercise].self, from: $0) }
        return WorkoutItem(
            id: id, title: title, notes: notes,
            createdAt: createdAt, updatedAt: updatedAt,
            importance: Importance(rawValue: importanceRaw) ?? .normal,
            anchor: try decode(anchorB64),
            completion: try decode(completionB64),
            tags: tags.map(Tag.from),
            plannedExercises: planned,
            estimatedKcal: estimatedKcal, actualKcal: actualKcal,
            actualExercises: actual, healthKitWorkoutID: healthKitWorkoutID
        )
    }
}

// MARK: - MealItem

struct SnapshotMeal: Codable {
    var id: UUID
    var title: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var importanceRaw: Int
    var anchorB64: String
    var completionB64: String
    var tags: [SnapshotTag]
    var recipeID: String
    var servings: Double
    var targetKcal: Int
    var actualKcal: Int?
    var loggedMacrosB64: String?
    var healthKitCorrelationID: String?

    init(from item: MealItem) throws {
        id = item.id; title = item.title; notes = item.notes
        createdAt = item.createdAt; updatedAt = item.updatedAt
        importanceRaw = item.importance.rawValue
        anchorB64 = try item.anchor.encoded().base64
        completionB64 = try item.completion.encoded().base64
        tags = item.tags.map(\.snapshot)
        recipeID = item.recipeID
        servings = item.servings
        targetKcal = item.targetKcal
        actualKcal = item.actualKcal
        loggedMacrosB64 = item.loggedMacros.flatMap { try? JSONEncoder().encode($0) }?.base64
        healthKitCorrelationID = item.healthKitCorrelationID
    }

    func toItem() throws -> MealItem {
        let macros = loggedMacrosB64.flatMap { Data(base64Encoded: $0) }
            .flatMap { try? JSONDecoder().decode(Macros.self, from: $0) }
        return MealItem(
            id: id, title: title, notes: notes,
            createdAt: createdAt, updatedAt: updatedAt,
            importance: Importance(rawValue: importanceRaw) ?? .normal,
            anchor: try decode(anchorB64),
            completion: try decode(completionB64),
            tags: tags.map(Tag.from),
            recipeID: recipeID, servings: servings,
            targetKcal: targetKcal, actualKcal: actualKcal,
            loggedMacros: macros, healthKitCorrelationID: healthKitCorrelationID
        )
    }
}

// MARK: - Habit

struct SnapshotHabit: Codable {
    var id: UUID
    var name: String
    var frequency: HabitFrequency
    var timeHint: TimeOfDay?
    var targetDurationSeconds: Double?
    var forgiveness: HabitForgiveness
    var recurrenceRuleRaw: String
    var createdAt: Date
    var isArchived: Bool

    init(from habit: Habit) {
        id = habit.id; name = habit.name
        frequency = habit.frequency; timeHint = habit.timeHint
        targetDurationSeconds = habit.targetDuration.map { Double($0.components.seconds) }
        forgiveness = habit.forgiveness
        recurrenceRuleRaw = habit.recurrenceRule.raw
        createdAt = habit.createdAt; isArchived = habit.isArchived
    }

    func toHabit() -> Habit {
        Habit(
            id: id, name: name, frequency: frequency, timeHint: timeHint,
            targetDuration: targetDurationSeconds.map { .seconds($0) },
            recurrenceRule: RecurrenceRule(raw: recurrenceRuleRaw),
            forgiveness: forgiveness, createdAt: createdAt, isArchived: isArchived
        )
    }
}

// MARK: - Decode helper

private func decode<T>(_ base64: String) throws -> T where T: Decodable {
    guard let data = Data(base64Encoded: base64) else {
        throw SnapshotError.invalidBase64
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(T.self, from: data)
}

// MARK: - Anchor/Completion decode shims

private func decode(_ base64: String) throws -> Anchor {
    guard let data = Data(base64Encoded: base64) else { throw SnapshotError.invalidBase64 }
    return try Anchor.decoded(from: data)
}

private func decode(_ base64: String) throws -> Completion {
    guard let data = Data(base64Encoded: base64) else { throw SnapshotError.invalidBase64 }
    return try Completion.decoded(from: data)
}

// MARK: - Errors

enum SnapshotError: LocalizedError {
    case invalidBase64
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .invalidBase64:           return "Backup file is corrupt (invalid encoding)."
        case .unsupportedVersion(let v): return "Backup version \(v) is not supported by this app."
        }
    }
}
