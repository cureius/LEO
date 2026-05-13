import Foundation

/// The unifying protocol for every captured unit of user intent.
///
/// Concrete types: `TaskItem`, `EventItem`, `ReminderItem`, `AlarmItem`, `HabitInstanceItem`.
/// Use `any Item` at the boundary (timeline, repositories) to embrace heterogeneity.
public protocol Item: Identifiable, Hashable, Sendable {
    /// Stable identity across persistence and sync.
    var id: UUID { get }
    var title: String { get set }
    /// Single-line note, max 280 chars enforced at repository boundary.
    var notes: String? { get set }
    /// All dates stored UTC. Interpret with Calendar.current at display time.
    var createdAt: Date { get }
    var updatedAt: Date { get set }
    var importance: Importance { get set }
    var anchor: Anchor { get set }
    var completion: Completion { get set }
    var tags: [Tag] { get set }
    /// RFC 5545 RRULE string stored on every occurrence of a recurring item.
    /// Nil for one-off items. Accessed via dynamic dispatch on `any Item`.
    var rruleRaw: String? { get }
}

// MARK: - Shared helpers available on any Item

extension Item {
    /// Default: non-recurring types return nil without needing a stored property.
    public var rruleRaw: String? { nil }

    var isCompleted: Bool { completion.isFinished }

    var isOverdue: Bool {
        guard !completion.isFinished else { return false }
        switch anchor {
        case .dueAt(let d):        return d < Date.now
        case .timeBlock(_, let e): return e < Date.now
        case .point(let d):        return d < Date.now
        default:                   return false
        }
    }
}
