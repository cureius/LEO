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

    /// Secondary sort key used when two items share the same `sortDate`.
    /// Point-in-time items (reminders, alarms) fire at an exact moment and
    /// should appear before time blocks that merely *begin* at that moment.
    var sortPriority: Int {
        switch self {
        case .point:     return 0   // fires at the exact instant
        case .dueAt:     return 1   // deadline — treat like a point
        case .timeBlock: return 2   // block that starts at this time
        default:         return 3
        }
    }

    /// True when this is a time block that covers essentially the whole day.
    ///
    /// Accepts two conventions:
    /// - **Midnight-to-midnight** (00:00 → 00:00 next day) — EK/Google Calendar standard.
    /// - **Midnight-to-23:59** (00:00 → 23:59) — used by some third-party calendar apps.
    ///
    /// Both must start at midnight and span at least 23 h 59 min (86 340 s).
    /// Uses direct component extraction to tolerate sub-second precision in stored dates.
    var isAllDayBlock: Bool {
        guard case .timeBlock(let s, let e) = self else { return false }
        let cal = Calendar.current
        let startH = cal.component(.hour,   from: s)
        let startM = cal.component(.minute, from: s)
        let endH   = cal.component(.hour,   from: e)
        let endM   = cal.component(.minute, from: e)
        let startsAtMidnight  = startH == 0  && startM == 0
        let endsAtMidnight    = endH   == 0  && endM   == 0
        let endsAt2359        = endH   == 23 && endM   == 59
        let spansFullDay      = e.timeIntervalSince(s) >= 86_340  // ≥ 23 h 59 min
        return startsAtMidnight && (endsAtMidnight || endsAt2359) && spansFullDay
    }
}
