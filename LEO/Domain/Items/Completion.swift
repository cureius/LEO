import Foundation

/// Lifecycle state for an Item. Completion carries a timestamp for analytics.
public enum Completion: Hashable, Sendable, Codable {
    case open
    case completed(at: Date)
    case skipped(at: Date, reason: String?)
    case dismissed

    var isFinished: Bool {
        switch self {
        case .open:      return false
        case .completed: return true
        case .skipped:   return true
        case .dismissed: return true
        }
    }

    var completedAt: Date? {
        if case .completed(let date) = self { return date }
        return nil
    }

    /// Used by ItemPredicate to filter by completion state.
    enum Filter: Hashable, Sendable {
        case open
        case finished
        case all
    }
}
