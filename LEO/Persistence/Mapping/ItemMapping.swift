import Foundation

// MARK: - Anchor encoding helpers

private let jsonEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    return e
}()

private let jsonDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

// MARK: - Anchor ↔ Data

extension Anchor {
    func encoded() throws -> Data { try jsonEncoder.encode(AnchorCodable(self)) }
    static func decoded(from data: Data) throws -> Anchor {
        try jsonDecoder.decode(AnchorCodable.self, from: data).anchor
    }
}

private struct AnchorCodable: Codable {
    let anchor: Anchor

    enum CodingKeys: String, CodingKey { case type, date, start, end, trigger }

    init(_ anchor: Anchor) { self.anchor = anchor }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch anchor {
        case .untimed:
            try c.encode("untimed", forKey: .type)
        case .dueAt(let d):
            try c.encode("dueAt", forKey: .type)
            try c.encode(d, forKey: .date)
        case .timeBlock(let s, let e):
            try c.encode("timeBlock", forKey: .type)
            try c.encode(s, forKey: .start)
            try c.encode(e, forKey: .end)
        case .point(let d):
            try c.encode("point", forKey: .type)
            try c.encode(d, forKey: .date)
        case .location(let trigger):
            try c.encode("location", forKey: .type)
            try c.encode(trigger, forKey: .trigger)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "untimed":
            anchor = .untimed
        case "dueAt":
            anchor = .dueAt(try c.decode(Date.self, forKey: .date))
        case "timeBlock":
            anchor = .timeBlock(start: try c.decode(Date.self, forKey: .start),
                                end: try c.decode(Date.self, forKey: .end))
        case "point":
            anchor = .point(try c.decode(Date.self, forKey: .date))
        case "location":
            anchor = .location(try c.decode(LocationTrigger.self, forKey: .trigger))
        default:
            anchor = .untimed
        }
    }
}

// MARK: - Completion ↔ Data

extension Completion {
    func encoded() throws -> Data { try jsonEncoder.encode(CompletionCodable(self)) }
    static func decoded(from data: Data) throws -> Completion {
        try jsonDecoder.decode(CompletionCodable.self, from: data).completion
    }
}

private struct CompletionCodable: Codable {
    let completion: Completion
    enum CodingKeys: String, CodingKey { case type, date, reason }
    init(_ c: Completion) { self.completion = c }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch completion {
        case .open:
            try c.encode("open", forKey: .type)
        case .completed(let d):
            try c.encode("completed", forKey: .type); try c.encode(d, forKey: .date)
        case .skipped(let d, let r):
            try c.encode("skipped", forKey: .type); try c.encode(d, forKey: .date)
            if let r { try c.encode(r, forKey: .reason) }
        case .dismissed:
            try c.encode("dismissed", forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "completed":
            completion = .completed(at: try c.decode(Date.self, forKey: .date))
        case "skipped":
            completion = .skipped(at: try c.decode(Date.self, forKey: .date),
                                  reason: try? c.decode(String.self, forKey: .reason))
        case "dismissed":
            completion = .dismissed
        default:
            completion = .open
        }
    }
}

// MARK: - Tag mapping

extension Tag {
    static func from(_ stored: StoredTag) -> Tag {
        Tag(id: stored.id, name: stored.name, color: TagColor(rawValue: stored.colorRaw) ?? .blue)
    }
}

// MARK: - Domain ↔ StoredTask

extension TaskItem {
    static func from(_ stored: StoredTask) throws -> TaskItem {
        TaskItem(
            id: stored.id,
            title: stored.title,
            notes: stored.notes,
            createdAt: stored.createdAt,
            updatedAt: stored.updatedAt,
            importance: Importance(rawValue: stored.importanceRaw) ?? .normal,
            anchor: try Anchor.decoded(from: stored.anchorData),
            completion: try Completion.decoded(from: stored.completionData),
            tags: stored.tags?.map(Tag.from) ?? [],
            deadline: stored.deadline,
            estimatedDuration: stored.estimatedDurationSeconds.map { .seconds($0) }
        )
    }
}

extension StoredTask {
    convenience init(from item: TaskItem, tags: [StoredTag]? = nil) throws {
        try self.init(
            id: item.id,
            title: item.title,
            notes: item.notes,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            importanceRaw: item.importance.rawValue,
            anchorData: item.anchor.encoded(),
            completionData: item.completion.encoded(),
            tags: tags,
            deadline: item.deadline,
            estimatedDurationSeconds: item.estimatedDuration.map { Double($0.components.seconds) }
        )
    }
}

// MARK: - Domain ↔ StoredEvent

extension EventItem {
    static func from(_ stored: StoredEvent) throws -> EventItem {
        let attendees = (try? JSONDecoder().decode([String].self, from: stored.attendeesData)) ?? []
        let externalRef = stored.externalRefData.flatMap { try? JSONDecoder().decode(ExternalRef.self, from: $0) }
        return EventItem(
            id: stored.id,
            title: stored.title,
            notes: stored.notes,
            createdAt: stored.createdAt,
            updatedAt: stored.updatedAt,
            importance: Importance(rawValue: stored.importanceRaw) ?? .normal,
            anchor: try Anchor.decoded(from: stored.anchorData),
            completion: try Completion.decoded(from: stored.completionData),
            tags: stored.tags?.map(Tag.from) ?? [],
            location: stored.location,
            attendees: attendees,
            externalRef: externalRef
        )
    }
}

extension StoredEvent {
    convenience init(from item: EventItem, tags: [StoredTag]? = nil) throws {
        let attendeesData = (try? JSONEncoder().encode(item.attendees)) ?? "[]".data(using: .utf8)!
        let externalRefData = try? JSONEncoder().encode(item.externalRef)
        try self.init(
            id: item.id,
            title: item.title,
            notes: item.notes,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            importanceRaw: item.importance.rawValue,
            anchorData: item.anchor.encoded(),
            completionData: item.completion.encoded(),
            tags: tags,
            location: item.location,
            attendeesData: attendeesData,
            externalRefData: externalRefData
        )
    }
}

// MARK: - Domain ↔ StoredReminder

extension ReminderItem {
    static func from(_ stored: StoredReminder) throws -> ReminderItem {
        let externalRef = stored.externalRefData.flatMap { try? JSONDecoder().decode(ExternalRef.self, from: $0) }
        return ReminderItem(
            id: stored.id,
            title: stored.title,
            notes: stored.notes,
            createdAt: stored.createdAt,
            updatedAt: stored.updatedAt,
            importance: Importance(rawValue: stored.importanceRaw) ?? .normal,
            anchor: try Anchor.decoded(from: stored.anchorData),
            completion: try Completion.decoded(from: stored.completionData),
            tags: stored.tags?.map(Tag.from) ?? [],
            leadTime: stored.leadTime,
            externalRef: externalRef
        )
    }
}

extension StoredReminder {
    convenience init(from item: ReminderItem, tags: [StoredTag]? = nil) throws {
        let externalRefData = try? JSONEncoder().encode(item.externalRef)
        try self.init(
            id: item.id, title: item.title, notes: item.notes,
            createdAt: item.createdAt, updatedAt: item.updatedAt,
            importanceRaw: item.importance.rawValue,
            anchorData: item.anchor.encoded(),
            completionData: item.completion.encoded(),
            tags: tags, leadTime: item.leadTime, externalRefData: externalRefData
        )
    }
}

// MARK: - Domain ↔ StoredAlarm

extension AlarmItem {
    static func from(_ stored: StoredAlarm) throws -> AlarmItem {
        AlarmItem(
            id: stored.id, title: stored.title, notes: stored.notes,
            createdAt: stored.createdAt, updatedAt: stored.updatedAt,
            importance: Importance(rawValue: stored.importanceRaw) ?? .urgent,
            anchor: try Anchor.decoded(from: stored.anchorData),
            completion: try Completion.decoded(from: stored.completionData),
            tags: stored.tags?.map(Tag.from) ?? [],
            soundProfile: AlarmSound(rawValue: stored.soundProfileRaw) ?? .default,
            escalates: stored.escalates
        )
    }
}

extension StoredAlarm {
    convenience init(from item: AlarmItem, tags: [StoredTag]? = nil) throws {
        try self.init(
            id: item.id, title: item.title, notes: item.notes,
            createdAt: item.createdAt, updatedAt: item.updatedAt,
            importanceRaw: item.importance.rawValue,
            anchorData: item.anchor.encoded(),
            completionData: item.completion.encoded(),
            tags: tags,
            soundProfileRaw: item.soundProfile.rawValue,
            escalates: item.escalates
        )
    }
}

// MARK: - Domain ↔ StoredHabitInstance

extension HabitInstanceItem {
    static func from(_ stored: StoredHabitInstance) throws -> HabitInstanceItem {
        HabitInstanceItem(
            id: stored.id, title: stored.title, notes: stored.notes,
            createdAt: stored.createdAt, updatedAt: stored.updatedAt,
            importance: Importance(rawValue: stored.importanceRaw) ?? .normal,
            anchor: try Anchor.decoded(from: stored.anchorData),
            completion: try Completion.decoded(from: stored.completionData),
            tags: stored.tags?.map(Tag.from) ?? [],
            habitID: stored.habitID,
            targetDuration: stored.targetDurationSeconds.map { .seconds($0) }
        )
    }
}
