import Foundation

// MARK: - GetTodayTool

struct GetTodayTool: LEOTool {
    struct Input: Decodable, Sendable {}
    struct Output: Encodable, Sendable {
        let items: [ItemSummary]
    }

    let definition = ToolDefinition(
        name: "get_today",
        description: "Returns all items scheduled for today, sorted by time.",
        inputSchema: ["type": .string("object"), "properties": .object([:]), "required": .array([])]
    )

    func run(_ input: Input, context: ToolContext) async throws -> Output {
        let today = Date.now
        let start = context.calendar.startOfDay(for: today)
        let end = context.calendar.date(byAdding: .day, value: 1, to: start) ?? today
        let items = try await context.itemRepository.fetch(predicate: .inDateInterval(DateInterval(start: start, end: end)))
        return Output(items: items.map(ItemSummary.init))
    }
}

// MARK: - GetWeekTool

struct GetWeekTool: LEOTool {
    struct Input: Decodable, Sendable {
        var startDate: String?  // ISO8601; defaults to today
    }
    struct Output: Encodable, Sendable {
        let items: [ItemSummary]
    }

    let definition = ToolDefinition(
        name: "get_week",
        description: "Returns items for the 7-day window starting from the given date (or today).",
        inputSchema: [
            "type": .string("object"),
            "properties": .object(["startDate": .object(["type": .string("string"), "description": .string("ISO8601 date string, e.g. 2026-05-08")])]),
            "required": .array([])
        ]
    )

    func run(_ input: Input, context: ToolContext) async throws -> Output {
        let start: Date
        if let s = input.startDate {
            start = ISO8601DateFormatter().date(from: s) ?? Date.now
        } else {
            start = context.calendar.startOfDay(for: Date.now)
        }
        let end = start.addingTimeInterval(7 * 86400)
        let items = try await context.itemRepository.fetch(predicate: .inDateInterval(DateInterval(start: start, end: end)))
        return Output(items: items.map(ItemSummary.init))
    }
}

// MARK: - FindFreeSlotsTool

struct FindFreeSlotsTool: LEOTool {
    struct Input: Decodable, Sendable {
        let durationMinutes: Int
        var startDate: String?
        var endDate: String?
    }
    struct Output: Encodable, Sendable {
        let slots: [SlotSummary]
    }
    struct SlotSummary: Encodable, Sendable {
        let start: String
        let end: String
    }

    let definition = ToolDefinition(
        name: "find_free_slots",
        description: "Returns candidate free time slots of the given duration in the search window.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "durationMinutes": .object(["type": .string("integer")]),
                "startDate": .object(["type": .string("string")]),
                "endDate": .object(["type": .string("string")])
            ]),
            "required": .array([.string("durationMinutes")])
        ]
    )

    func run(_ input: Input, context: ToolContext) async throws -> Output {
        let iso = ISO8601DateFormatter()
        let start = input.startDate.flatMap { iso.date(from: $0) } ?? Date.now
        let end = input.endDate.flatMap { iso.date(from: $0) } ?? start.addingTimeInterval(7 * 86400)
        let duration = TimeInterval(input.durationMinutes * 60)

        let items = try await context.itemRepository.fetch(predicate: .inDateInterval(DateInterval(start: start, end: end)))
        let busyIntervals = items.compactMap { item -> DateInterval? in
            switch item.anchor {
            case .timeBlock(let s, let e): return DateInterval(start: s, end: e)
            default: return nil
            }
        }.sorted { $0.start < $1.start }

        var slots: [SlotSummary] = []
        var cursor = start
        let workdayStart = 9 * 3600.0
        let workdayEnd = 18 * 3600.0

        while cursor < end && slots.count < 5 {
            // Snap to workday
            let dayStart = context.calendar.startOfDay(for: cursor)
            let wStart = dayStart.addingTimeInterval(workdayStart)
            let wEnd = dayStart.addingTimeInterval(workdayEnd)
            if cursor < wStart { cursor = wStart }
            if cursor >= wEnd {
                cursor = context.calendar.date(byAdding: .day, value: 1, to: dayStart)!.addingTimeInterval(workdayStart)
                continue
            }

            let slotEnd = cursor.addingTimeInterval(duration)
            let conflicts = busyIntervals.filter { $0.intersects(DateInterval(start: cursor, end: slotEnd)) }
            if conflicts.isEmpty && slotEnd <= wEnd {
                slots.append(SlotSummary(start: iso.string(from: cursor), end: iso.string(from: slotEnd)))
                cursor = slotEnd
            } else {
                cursor = cursor.addingTimeInterval(15 * 60)
            }
        }

        return Output(slots: slots)
    }
}

// MARK: - GetItemTool

struct GetItemTool: LEOTool {
    struct Input: Decodable, Sendable { let id: String }
    struct Output: Encodable, Sendable { let item: ItemSummary? }

    let definition = ToolDefinition(
        name: "get_item",
        description: "Returns the details of a single item by UUID.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object(["id": .object(["type": .string("string")])]),
            "required": .array([.string("id")])
        ]
    )

    func run(_ input: Input, context: ToolContext) async throws -> Output {
        guard let uuid = UUID(uuidString: input.id) else { return Output(item: nil) }
        let items = try await context.itemRepository.fetch(predicate: .byID(uuid))
        return Output(item: items.first.map(ItemSummary.init))
    }
}

// MARK: - ItemSummary (output format for read tools)

struct ItemSummary: Encodable, Sendable {
    let id: String
    let title: String
    let type: String
    let anchor: String
    let isCompleted: Bool
    let importance: Int

    init(_ item: any Item) {
        self.id = item.id.uuidString
        self.title = item.title
        self.type = String(describing: Swift.type(of: item))
        self.isCompleted = item.isCompleted
        self.importance = item.importance.rawValue

        switch item.anchor {
        case .untimed:              self.anchor = "untimed"
        case .dueAt(let d):         self.anchor = "due:\(ISO8601DateFormatter().string(from: d))"
        case .timeBlock(let s, let e): self.anchor = "block:\(ISO8601DateFormatter().string(from: s))–\(ISO8601DateFormatter().string(from: e))"
        case .point(let d):         self.anchor = "point:\(ISO8601DateFormatter().string(from: d))"
        case .location:             self.anchor = "location"
        }
    }
}
