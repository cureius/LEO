import ActivityKit
import Foundation

// MARK: - Activity Attributes

/// Defines the static + dynamic content for the "next event" Live Activity.
struct NextEventActivityAttributes: ActivityAttributes {
    /// Static: doesn't change during the activity's lifetime
    let eventID: UUID
    let eventTitle: String
    let location: String?

    /// Dynamic: updated as time progresses
    struct ContentState: Codable, Hashable {
        var startDate: Date
        var endDate: Date
        var minutesUntilStart: Int
        var state: EventState

        enum EventState: String, Codable, Hashable {
            case upcoming   // > 0 minutes away
            case ongoing    // start ≤ now ≤ end
            case past       // ended
        }
    }
}

// MARK: - Activity Driver

/// Monitors the item repository for the next event and manages the Live Activity lifecycle.
/// Started by `LEOApp` after the environment is ready.
actor NextEventActivityDriver {
    private let itemRepository: ItemRepository
    private var currentActivity: Activity<NextEventActivityAttributes>?
    private var currentEventID: UUID? = nil

    init(itemRepository: ItemRepository) {
        self.itemRepository = itemRepository
    }

    // MARK: - Lifecycle

    func start() async {
        while true {
            await tick()
            try? await Task.sleep(for: .seconds(60))
        }
    }

    // MARK: - Tick

    private func tick() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let nextEvent = await fetchNextEvent()

        guard let event = nextEvent, case .timeBlock(let start, let end) = event.anchor else {
            await endCurrentActivity()
            return
        }

        let minutesUntil = Int(start.timeIntervalSinceNow / 60)
        // Only show Live Activity for events starting within 60 minutes
        guard minutesUntil <= 60 else {
            await endCurrentActivity()
            return
        }

        let state = contentState(for: event, start: start, end: end)

        if let activity = currentActivity, currentEventID == event.id {
            // Update existing activity
            await activity.update(ActivityContent(state: state, staleDate: nil))
        } else {
            // End old, start new
            await endCurrentActivity()
            await startActivity(for: event, start: start, end: end, initialState: state)
        }

        // End if event is past
        if state.state == .past {
            try? await Task.sleep(for: .seconds(5 * 60))
            await endCurrentActivity()
        }
    }

    // MARK: - Private helpers

    private func fetchNextEvent() async -> EventItem? {
        let now = Date.now
        let window = DateInterval(start: now, duration: 24 * 3600)
        let items = (try? await itemRepository.fetch(predicate: .inDateInterval(window))) ?? []
        return items
            .compactMap { $0 as? EventItem }
            .filter { !$0.isCompleted }
            .sorted { a, b in
                (a.anchor.sortDate ?? .distantFuture) < (b.anchor.sortDate ?? .distantFuture)
            }
            .first
    }

    private func startActivity(for event: EventItem, start: Date, end: Date, initialState: NextEventActivityAttributes.ContentState) async {
        let attributes = NextEventActivityAttributes(
            eventID: event.id,
            eventTitle: event.title,
            location: event.location
        )
        do {
            let activity = try Activity<NextEventActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            currentEventID = event.id
        } catch {
            // Live Activities not supported (e.g., iPad without Dynamic Island)
        }
    }

    private func endCurrentActivity() async {
        if let activity = currentActivity {
            var state = await activity.content.state
            state.state = .past
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date.now.addingTimeInterval(5 * 60)))
            currentActivity = nil
            currentEventID = nil
        }
    }

    private func contentState(for event: EventItem, start: Date, end: Date) -> NextEventActivityAttributes.ContentState {
        let now = Date.now
        let eventState: NextEventActivityAttributes.ContentState.EventState
        if now < start { eventState = .upcoming }
        else if now <= end { eventState = .ongoing }
        else { eventState = .past }

        return NextEventActivityAttributes.ContentState(
            startDate: start,
            endDate: end,
            minutesUntilStart: max(0, Int(start.timeIntervalSinceNow / 60)),
            state: eventState
        )
    }
}
