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

    /// A plain edit must advance `updatedAt`, or cloud sync's `updatedAt > lastSync`
    /// push filter never uploads it. This was the root cause of completions made on
    /// one device not appearing on another.
    func test_update_bumpsUpdatedAt() async throws {
        let repo = ItemRepository(controller: PersistenceController(useInMemory: true))
        var task = TaskItem(title: "Complete me",
                            updatedAt: Date(timeIntervalSince1970: 1_000),
                            anchor: .untimed)
        try await repo.add(task)

        task.completion = .completed(at: .now)
        try await repo.update(task)   // caller did NOT touch updatedAt

        let stored = try await repo.fetch(predicate: .all).first { $0.id == task.id }
        XCTAssertNotNil(stored)
        XCTAssertGreaterThan(stored!.updatedAt.timeIntervalSince1970, 1_000,
                             "update() must refresh updatedAt so the change is syncable")
    }

    /// Applying a change pulled from the cloud (or mirrored from EventKit) must keep
    /// its authoritative timestamp — otherwise last-writer-wins re-stamps it and the
    /// row bounces straight back to the device it came from.
    func test_update_preservesTimestampWhenRequested() async throws {
        let repo = ItemRepository(controller: PersistenceController(useInMemory: true))
        let remoteTime = Date(timeIntervalSince1970: 2_000)
        var task = TaskItem(title: "From cloud", updatedAt: remoteTime, anchor: .untimed)
        try await repo.add(task)

        task.title = "From cloud (v2)"
        var incoming = task
        incoming.updatedAt = remoteTime
        try await repo.update(incoming, preservingTimestamp: true)

        let stored = try await repo.fetch(predicate: .all).first { $0.id == task.id }
        XCTAssertEqual(stored?.updatedAt.timeIntervalSince1970, 2_000,
                       "sync-applied timestamp must be preserved to avoid an echo loop")
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
