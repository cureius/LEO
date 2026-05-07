import Foundation

/// The time point or window an Item is bound to.
/// - `untimed`: lives in the Inbox until the user gives it a time.
/// - `dueAt`: hard deadline with no scheduled work block (task is open, due by this date).
/// - `timeBlock`: a calendar event occupying start→end.
/// - `point`: a reminder or alarm fires at an exact moment.
/// - `location`: fires on entering or leaving a geographic region.
///
/// All `Date` values are stored UTC. Interpretation uses `Calendar.current` at display time.
public enum Anchor: Hashable, Sendable, Codable {
    case untimed
    case dueAt(Date)
    case timeBlock(start: Date, end: Date)
    case point(Date)
    case location(LocationTrigger)

    /// The canonical "sort time" of this anchor for timeline ordering.
    var sortDate: Date? {
        switch self {
        case .untimed:               return nil
        case .dueAt(let d):          return d
        case .timeBlock(let s, _):   return s
        case .point(let d):          return d
        case .location:              return nil
        }
    }

    var isUntimed: Bool {
        if case .untimed = self { return true }
        return false
    }
}
