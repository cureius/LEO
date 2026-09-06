import XCTest
@testable import LEO

/// `SyncPolicy` is deliberately pure (no network, no actor, no login) so it can be
/// tested directly against edge cases — see its own doc comment in SupabaseSync.swift.
final class SyncPolicyTests: XCTestCase {

    // MARK: - idsToTombstone (pre-existing, no coverage existed before this change)

    func test_idsToTombstone_onlyTombstonesRowsThatAreActiveRemoteAbsentLocalAndKnown() {
        let result = SyncPolicy.idsToTombstone(
            activeRemoteIDs: ["a", "b", "c"],
            localIDs: ["a"],
            knownIDs: ["b", "d"]
        )
        // "b": remote-active, locally absent, known -> tombstone.
        // "c": remote-active, locally absent, but NOT known -> could be a row this
        //      device never successfully applied, not a real deletion -> leave alone.
        XCTAssertEqual(result, ["b"])
    }

    func test_shouldApplyRemote_takesRemoteWhenNothingLocalExists() {
        XCTAssertTrue(SyncPolicy.shouldApplyRemote(remoteUpdatedAt: .now, localUpdatedAt: nil))
    }

    func test_shouldApplyRemote_lastWriterWins() {
        let earlier = Date.now
        let later = earlier.addingTimeInterval(60)
        XCTAssertTrue(SyncPolicy.shouldApplyRemote(remoteUpdatedAt: later, localUpdatedAt: earlier))
        XCTAssertFalse(SyncPolicy.shouldApplyRemote(remoteUpdatedAt: earlier, localUpdatedAt: later))
    }

    // MARK: - ledgerEligibleIDs (new — the tombstone-safety mechanism for pushed
    // EventKit-mirrored items; see SyncPolicy.ledgerEligibleIDs's doc comment)

    func test_ledgerEligibleIDs_excludesExternallyManagedItems() {
        let result = SyncPolicy.ledgerEligibleIDs([
            (id: "task-1", isExternallyManaged: false),
            (id: "calendar-event-1", isExternallyManaged: true),
            (id: "task-2", isExternallyManaged: false),
        ])
        XCTAssertEqual(Set(result), ["task-1", "task-2"])
    }

    func test_ledgerEligibleIDs_allExternallyManaged_yieldsEmpty() {
        let result = SyncPolicy.ledgerEligibleIDs([
            (id: "calendar-event-1", isExternallyManaged: true),
            (id: "reminder-1", isExternallyManaged: true),
        ])
        XCTAssertTrue(result.isEmpty)
    }

    func test_ledgerEligibleIDs_noneExternallyManaged_yieldsAll() {
        let result = SyncPolicy.ledgerEligibleIDs([
            (id: "task-1", isExternallyManaged: false),
            (id: "task-2", isExternallyManaged: false),
        ])
        XCTAssertEqual(Set(result), ["task-1", "task-2"])
    }
}
