import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "itemdetail")

@MainActor
@Observable
final class ItemDetailViewModel {
    // MARK: - Editable draft fields (common to all Item types)
    var title: String = ""
    var notes: String = ""
    var importance: Importance = .normal
    var anchor: Anchor = .untimed
    var tags: [Tag] = []

    // MARK: - TaskItem extras
    var deadline: Date? = nil
    var estimatedDurationHours: Double = 0

    // MARK: - EventItem extras
    var location: String = ""
    var attendees: [String] = []

    // MARK: - ReminderItem extras
    var leadTimeMinutes: Int = 0

    // MARK: - AlarmItem extras
    var soundProfile: AlarmSound = .default
    var escalates: Bool = true

    // MARK: - Recurrence
    var recurrenceRule: RecurrenceRule? = nil

    // MARK: - HabitInstanceItem (read-only here; habits edited separately)

    // MARK: - State
    private(set) var isSaving = false
    private(set) var saveError: String? = nil

    let originalItem: (any Item)?
    private let repository: ItemRepository

    init(item: (any Item)?, repository: ItemRepository) {
        self.originalItem = item
        self.repository = repository
        if let item { populate(from: item) }
    }

    // MARK: - Validation

    var isValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var validationError: String? {
        if title.trimmingCharacters(in: .whitespaces).isEmpty { return "Title is required" }
        if case .timeBlock(let s, let e) = anchor, e <= s { return "End time must be after start" }
        return nil
    }

    // MARK: - Save

    func save() async -> Bool {
        guard isValid else { return false }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            if let rule = recurrenceRule,
               let parsed = try? rule.parsed(),
               let anchorDate = anchor.sortDate {
                try await saveRecurring(parsed: parsed, anchorStart: anchorDate)
            } else {
                let item = buildItem()
                if originalItem != nil {
                    try await repository.update(item)
                } else {
                    try await repository.add(item)
                }
            }
            return true
        } catch {
            saveError = error.localizedDescription
            logger.error("ItemDetailViewModel save error: \(error)")
            return false
        }
    }

    private func saveRecurring(parsed: RRule, anchorStart: Date) async throws {
        // Expand occurrences for 1 year from the anchor start.
        let end = Calendar.current.date(byAdding: .year, value: 1, to: anchorStart)
                  ?? anchorStart.addingTimeInterval(365 * 86400)
        let window = DateInterval(start: anchorStart, end: end)
        let dates = (try? await RecurrenceEngine.shared.occurrences(
            rule: parsed, anchorStart: anchorStart, in: window
        )) ?? [anchorStart]

        // If editing an existing item, remove just that one occurrence first.
        if let original = originalItem {
            try await repository.delete(id: original.id)
        }

        let items: [any Item] = dates.map { date in
            buildOccurrence(anchor: occurrenceAnchor(for: date))
        }
        try await repository.addBatch(items)
    }

    /// Produce an anchor for a specific occurrence date, preserving the original anchor type and duration.
    private func occurrenceAnchor(for date: Date) -> Anchor {
        switch anchor {
        case .point:               return .point(date)
        case .dueAt:               return .dueAt(date)
        case .timeBlock(let s, let e):
            let dur = e.timeIntervalSince(s)
            return .timeBlock(start: date, end: date.addingTimeInterval(dur))
        default:                   return .point(date)
        }
    }

    /// Build a single occurrence item with a given anchor (always open, always new UUID).
    private func buildOccurrence(anchor occAnchor: Anchor) -> any Item {
        let now = Date.now
        let cleanNotes: String? = notes.isEmpty ? nil : String(notes.prefix(280))
        let createdAt = originalItem?.createdAt ?? now
        switch itemType {
        case .task:
            return TaskItem(
                id: UUID(), title: title, notes: cleanNotes,
                createdAt: createdAt, updatedAt: now,
                importance: importance, anchor: occAnchor,
                completion: .open, tags: tags,
                deadline: deadline,
                estimatedDuration: estimatedDurationHours > 0 ? .seconds(estimatedDurationHours * 3600) : nil
            )
        case .event:
            return EventItem(
                id: UUID(), title: title, notes: cleanNotes,
                createdAt: createdAt, updatedAt: now,
                importance: importance, anchor: occAnchor,
                completion: .open, tags: tags,
                location: location.isEmpty ? nil : location,
                attendees: attendees
            )
        case .reminder:
            return ReminderItem(
                id: UUID(), title: title, notes: cleanNotes,
                createdAt: createdAt, updatedAt: now,
                importance: importance, anchor: occAnchor,
                completion: .open, tags: tags,
                leadTime: leadTimeMinutes > 0 ? TimeInterval(leadTimeMinutes * 60) : nil
            )
        case .alarm:
            return AlarmItem(
                id: UUID(), title: title, notes: cleanNotes,
                createdAt: createdAt, updatedAt: now,
                importance: importance, anchor: occAnchor,
                completion: .open, tags: tags,
                soundProfile: soundProfile, escalates: escalates
            )
        }
    }

    func delete() async -> Bool {
        guard let id = originalItem?.id else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.delete(id: id)
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    // MARK: - Private

    private func populate(from item: any Item) {
        title = item.title
        notes = item.notes ?? ""
        importance = item.importance
        anchor = item.anchor
        tags = item.tags

        if let t = item as? TaskItem {
            deadline = t.deadline
            if let dur = t.estimatedDuration {
                estimatedDurationHours = Double(dur.components.seconds) / 3600
            }
        } else if let e = item as? EventItem {
            location = e.location ?? ""
            attendees = e.attendees
        } else if let r = item as? ReminderItem {
            leadTimeMinutes = r.leadTime.map { Int($0 / 60) } ?? 0
        } else if let a = item as? AlarmItem {
            soundProfile = a.soundProfile
            escalates = a.escalates
        }
    }

    private func buildItem() -> any Item {
        let now = Date.now
        let cleanNotes: String? = notes.isEmpty ? nil : String(notes.prefix(280))
        let id = originalItem?.id ?? UUID()
        let createdAt = (originalItem?.createdAt) ?? now

        switch itemType {
        case .task:
            return TaskItem(
                id: id, title: title, notes: cleanNotes,
                createdAt: createdAt, updatedAt: now,
                importance: importance, anchor: anchor,
                completion: originalItem?.completion ?? .open, tags: tags,
                deadline: deadline,
                estimatedDuration: estimatedDurationHours > 0 ? .seconds(estimatedDurationHours * 3600) : nil
            )
        case .event:
            return EventItem(
                id: id, title: title, notes: cleanNotes,
                createdAt: createdAt, updatedAt: now,
                importance: importance, anchor: anchor,
                completion: originalItem?.completion ?? .open, tags: tags,
                location: location.isEmpty ? nil : location,
                attendees: attendees
            )
        case .reminder:
            return ReminderItem(
                id: id, title: title, notes: cleanNotes,
                createdAt: createdAt, updatedAt: now,
                importance: importance, anchor: anchor,
                completion: originalItem?.completion ?? .open, tags: tags,
                leadTime: leadTimeMinutes > 0 ? TimeInterval(leadTimeMinutes * 60) : nil
            )
        case .alarm:
            return AlarmItem(
                id: id, title: title, notes: cleanNotes,
                createdAt: createdAt, updatedAt: now,
                importance: importance, anchor: anchor,
                completion: originalItem?.completion ?? .open, tags: tags,
                soundProfile: soundProfile, escalates: escalates
            )
        }
    }

    enum ItemType { case task, event, reminder, alarm }

    private var itemType: ItemType {
        if originalItem is EventItem { return .event }
        if originalItem is ReminderItem { return .reminder }
        if originalItem is AlarmItem { return .alarm }
        // Infer from anchor
        switch anchor {
        case .timeBlock: return .event
        case .location:  return .reminder
        default:         return .task
        }
    }
}
