import XCTest
@testable import LEO

final class DiffTests: XCTestCase {

    func test_emptyDiff() {
        let diff = Diff(changes: [])
        XCTAssertTrue(diff.isEmpty)
        XCTAssertEqual(diff.addCount, 0)
        XCTAssertEqual(diff.updateCount, 0)
        XCTAssertEqual(diff.deleteCount, 0)
    }

    func test_diffCounts() {
        let id1 = UUID()
        let id2 = UUID()
        let box = AnyItemBox(id: UUID(), typeDescription: "TaskItem")
        let diff = Diff(changes: [
            .add(box),
            .update(id: id1, patch: ItemPatch(title: "New title")),
            .delete(id: id2),
        ], rationale: "Test diff")
        XCTAssertEqual(diff.addCount, 1)
        XCTAssertEqual(diff.updateCount, 1)
        XCTAssertEqual(diff.deleteCount, 1)
        XCTAssertFalse(diff.isEmpty)
        XCTAssertEqual(diff.rationale, "Test diff")
    }

    func test_diffEquality() {
        let id = UUID()
        let d1 = Diff(id: id, changes: [], rationale: "same")
        let d2 = Diff(id: id, changes: [], rationale: "same")
        XCTAssertEqual(d1, d2)
    }
}
