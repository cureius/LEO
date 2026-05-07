import XCTest
import SwiftData
@testable import LEO

final class PersistenceControllerTests: XCTestCase {

    func test_inMemoryContainerOpens() throws {
        let controller = PersistenceController(useInMemory: true)
        XCTAssertNotNil(controller.container)
    }

    func test_insertAndFetchTask() async throws {
        let controller = PersistenceController(useInMemory: true)
        let repo = ItemRepository(controller: controller)
        let task = TaskItem(title: "Persistence test task", anchor: .dueAt(.now.addingTimeInterval(3600)))
        try await repo.add(task)

        let fetched = try await repo.fetch(predicate: .all)
        XCTAssertTrue(fetched.contains(where: { $0.id == task.id }))
    }

    func test_insertAndFetchEvent() async throws {
        let controller = PersistenceController(useInMemory: true)
        let repo = ItemRepository(controller: controller)
        let event = EventItem(title: "Test event",
                               anchor: .timeBlock(start: .now, end: .now.addingTimeInterval(3600)),
                               attendees: ["alice@example.com"])
        try await repo.add(event)

        let fetched = try await repo.fetch(predicate: .all)
        let found = fetched.first(where: { $0.id == event.id }) as? EventItem
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.attendees, ["alice@example.com"])
    }

    func test_deleteItem() async throws {
        let controller = PersistenceController(useInMemory: true)
        let repo = ItemRepository(controller: controller)
        let task = TaskItem(title: "To be deleted", anchor: .untimed)
        try await repo.add(task)
        try await repo.delete(id: task.id)

        let fetched = try await repo.fetch(predicate: .all)
        XCTAssertFalse(fetched.contains(where: { $0.id == task.id }))
    }

    func test_filterUntimed() async throws {
        let controller = PersistenceController(useInMemory: true)
        let repo = ItemRepository(controller: controller)
        let timed = TaskItem(title: "Timed", anchor: .dueAt(.now))
        let untimed = TaskItem(title: "Untimed", anchor: .untimed)
        try await repo.add(timed)
        try await repo.add(untimed)

        let untimedItems = try await repo.fetch(predicate: .untimed)
        XCTAssertTrue(untimedItems.contains(where: { $0.id == untimed.id }))
        XCTAssertFalse(untimedItems.contains(where: { $0.id == timed.id }))
    }
}
