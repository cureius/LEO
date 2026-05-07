import XCTest
@testable import LEO

final class ItemTests: XCTestCase {

    func test_taskItem_conformsToItem() {
        let task = TaskItem(title: "Test task", anchor: .untimed)
        XCTAssertEqual(task.title, "Test task")
        XCTAssertFalse(task.isCompleted)
        XCTAssertTrue(task.anchor.isUntimed)
    }

    func test_eventItem_conformsToItem() {
        let start = Date.now
        let end = start.addingTimeInterval(3600)
        let event = EventItem(title: "Meeting", anchor: .timeBlock(start: start, end: end))
        XCTAssertFalse(event.isCompleted)
        XCTAssertEqual(event.anchor.sortDate, start)
    }

    func test_reminderItem_conformsToItem() {
        let fire = Date.now.addingTimeInterval(600)
        let reminder = ReminderItem(title: "Pick up groceries", anchor: .point(fire))
        XCTAssertEqual(reminder.anchor.sortDate, fire)
    }

    func test_alarmItem_defaultsUrgent() {
        let alarm = AlarmItem(title: "Wake up", anchor: .point(.now.addingTimeInterval(28800)))
        XCTAssertEqual(alarm.importance, .urgent)
        XCTAssertTrue(alarm.escalates)
    }

    func test_habitInstanceItem_holdsHabitID() {
        let habitID = UUID()
        let instance = HabitInstanceItem(title: "Gym", anchor: .untimed, habitID: habitID)
        XCTAssertEqual(instance.habitID, habitID)
    }

    func test_completion_finishedStates() {
        XCTAssertTrue(Completion.completed(at: .now).isFinished)
        XCTAssertTrue(Completion.skipped(at: .now, reason: nil).isFinished)
        XCTAssertTrue(Completion.dismissed.isFinished)
        XCTAssertFalse(Completion.open.isFinished)
    }

    func test_importance_ordering() {
        XCTAssertLessThan(Importance.low.rawValue, Importance.normal.rawValue)
        XCTAssertLessThan(Importance.normal.rawValue, Importance.high.rawValue)
        XCTAssertLessThan(Importance.high.rawValue, Importance.urgent.rawValue)
    }

    func test_anchor_encoding_roundTrip() throws {
        let anchors: [Anchor] = [
            .untimed,
            .dueAt(.now),
            .timeBlock(start: .now, end: .now.addingTimeInterval(3600)),
            .point(.now),
        ]
        for anchor in anchors {
            let data = try anchor.encoded()
            let decoded = try Anchor.decoded(from: data)
            // Verify type is preserved (not full equality since dates have sub-second differences from JSON)
            switch (anchor, decoded) {
            case (.untimed, .untimed): break
            case (.dueAt, .dueAt): break
            case (.timeBlock, .timeBlock): break
            case (.point, .point): break
            default: XCTFail("Anchor round-trip changed type: \(anchor) → \(decoded)")
            }
        }
    }
}
