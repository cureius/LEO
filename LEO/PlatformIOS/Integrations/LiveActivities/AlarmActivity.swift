import ActivityKit
import Foundation

// MARK: - Alarm Activity Attributes

struct AlarmActivityAttributes: ActivityAttributes {
    let alarmID: UUID
    let alarmTitle: String

    struct ContentState: Codable, Hashable {
        var fireDate: Date
        var snoozed: Bool
        var dismissed: Bool
    }
}

// MARK: - Alarm Activity Manager

actor AlarmActivityManager {
    private var currentActivity: Activity<AlarmActivityAttributes>?

    func start(for alarm: AlarmItem) async {
        guard case .point(let fireDate) = alarm.anchor,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = AlarmActivityAttributes(alarmID: alarm.id, alarmTitle: alarm.title)
        let state = AlarmActivityAttributes.ContentState(fireDate: fireDate, snoozed: false, dismissed: false)

        do {
            let activity = try Activity<AlarmActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: fireDate.addingTimeInterval(30 * 60)),
                pushType: nil
            )
            currentActivity = activity
        } catch {
            // Live Activities not available (older device without Dynamic Island)
        }
    }

    func dismiss() async {
        var state = await currentActivity?.content.state
        state?.dismissed = true
        if let state {
            await currentActivity?.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        currentActivity = nil
    }

    func snooze() async {
        var state = await currentActivity?.content.state
        state?.snoozed = true
        if let state {
            await currentActivity?.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        currentActivity = nil
    }
}
