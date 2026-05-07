import Foundation

/// Value type the repositories translate to SwiftData #Predicate calls.
/// Extensible: add new cases here when a new query pattern is needed.
enum ItemPredicate: Hashable, Sendable {
    case all
    case byID(UUID)
    case inDateInterval(DateInterval)
    case completionFilter(Completion.Filter)
    /// Items with `.untimed` anchor (Inbox candidates).
    case untimed
    /// Items anchored on a specific calendar day.
    case onDay(Date)
}
