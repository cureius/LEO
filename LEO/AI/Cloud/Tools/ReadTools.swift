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
    let type: String       // "event" | "task" | "reminder" | "alarm" | "habit" | "workout" | "meal"
    let schedule: String   // human-readable local time: "9:00 AM – 10:00 AM", "Due at 5:00 PM", "Untimed"
    let anchor: String     // machine-readable ISO8601 with local timezone offset, for tool inputs
    let isCompleted: Bool
    let importance: String // "low" | "normal" | "high" | "urgent"
    let notes: String?
    let location: String?  // events only

    init(_ item: any Item) {
        self.id = item.id.uuidString
        self.title = item.title
        self.isCompleted = item.isCompleted
        self.notes = item.notes.flatMap { $0.isEmpty ? nil : $0 }
        self.location = (item as? EventItem)?.location

        switch item {
        case is EventItem:         self.type = "event"
        case is TaskItem:          self.type = "task"
        case is ReminderItem:      self.type = "reminder"
        case is AlarmItem:         self.type = "alarm"
        case is HabitInstanceItem: self.type = "habit"
        case is WorkoutItem:       self.type = "workout"
        case is MealItem:          self.type = "meal"
        default:                   self.type = "item"
        }

        switch item.importance {
        case .low:    self.importance = "low"
        case .normal: self.importance = "normal"
        case .high:   self.importance = "high"
        case .urgent: self.importance = "urgent"
        }

        // Human-readable time in the device's local timezone
        let timeFmt = DateFormatter()
        timeFmt.timeStyle = .short
        timeFmt.dateStyle = .none
        timeFmt.timeZone = .current

        // ISO8601 with local timezone offset — used by propose_reschedule / propose_cancel
        let isoFmt = ISO8601DateFormatter()
        isoFmt.timeZone = .current

        switch item.anchor {
        case .untimed:
            self.schedule = "Untimed"
            self.anchor   = "untimed"
        case .dueAt(let d):
            self.schedule = "Due at \(timeFmt.string(from: d))"
            self.anchor   = "due:\(isoFmt.string(from: d))"
        case .timeBlock(let s, let e):
            if item.anchor.isAllDayBlock {
                self.schedule = "All day"
                self.anchor   = "allday:\(isoFmt.string(from: s))"
            } else {
                self.schedule = "\(timeFmt.string(from: s)) – \(timeFmt.string(from: e))"
                self.anchor   = "block:\(isoFmt.string(from: s))–\(isoFmt.string(from: e))"
            }
        case .point(let d):
            self.schedule = "At \(timeFmt.string(from: d))"
            self.anchor   = "point:\(isoFmt.string(from: d))"
        case .location:
            self.schedule = "Location-based"
            self.anchor   = "location"
        }
    }
}
