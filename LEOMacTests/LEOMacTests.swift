import XCTest
@testable import LEO

// Mac-specific unit tests live here — see plans/mac/conventions.md

#if canImport(Supabase)

/// Regression tests for the cloud-sync decision rules.
///
/// These cover the failure modes that cost user data rather than the happy path:
/// a row erased on every device because one local write failed, and a row that
/// re-applies forever because two different clocks were compared.
final class SyncPolicyTests: XCTestCase {

    // MARK: Delete propagation

    /// The data-loss case. A cloud row we never managed to store locally (unknown
    /// `kind`, corrupt payload, transient insert failure) is absent locally for a
    /// reason that has nothing to do with deletion. Tombstoning it would destroy
    /// real data on every other device.
    func testDoesNotTombstoneRowNeverHeldLocally() {
        let ids = SyncPolicy.idsToTombstone(
            activeRemoteIDs: ["never-decoded"],
            localIDs: [],
            knownIDs: []                       // never successfully synced here
        )
        XCTAssertTrue(ids.isEmpty, "A row this device never held must not be treated as deleted")
    }

    /// The case delete propagation exists for: we held it, the user deleted it, so
    /// the tombstone should follow to the other devices.
    func testTombstonesRowDeletedLocally() {
        let ids = SyncPolicy.idsToTombstone(
            activeRemoteIDs: ["deleted-here"],
            localIDs: [],
            knownIDs: ["deleted-here"]
        )
        XCTAssertEqual(ids, ["deleted-here"])
    }

    func testDoesNotTombstoneRowStillPresentLocally() {
        let ids = SyncPolicy.idsToTombstone(
            activeRemoteIDs: ["alive"],
            localIDs: ["alive"],
            knownIDs: ["alive"]
        )
        XCTAssertTrue(ids.isEmpty)
    }

    /// A mixed batch must isolate exactly the deleted row and leave the rest alone.
    func testTombstonesOnlyGenuinelyDeletedRows() {
        let ids = SyncPolicy.idsToTombstone(
            activeRemoteIDs: ["alive", "deleted-here", "never-decoded"],
            localIDs: ["alive"],
            knownIDs: ["alive", "deleted-here"]
        )
        XCTAssertEqual(ids, ["deleted-here"])
    }

    // MARK: Last-writer-wins

    func testRemoteAppliedWhenNothingLocal() {
        XCTAssertTrue(SyncPolicy.shouldApplyRemote(remoteUpdatedAt: .now, localUpdatedAt: nil))
    }

    func testNewerRemoteWins() {
        let local = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(SyncPolicy.shouldApplyRemote(remoteUpdatedAt: local.addingTimeInterval(60),
                                                   localUpdatedAt: local))
    }

    func testOlderRemoteDoesNotClobberNewerLocal() {
        let local = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(SyncPolicy.shouldApplyRemote(remoteUpdatedAt: local.addingTimeInterval(-60),
                                                    localUpdatedAt: local),
                       "A stale remote row must never overwrite a newer local edit")
    }

    /// Equal timestamps mean the same version. Re-applying would post a change
    /// notification, which schedules a push, which syncs again — so this must be a
    /// no-op or the device never settles.
    func testIdenticalTimestampIsNoOp() {
        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(SyncPolicy.shouldApplyRemote(remoteUpdatedAt: t, localUpdatedAt: t))
    }
}

/// EventKit-backed items must stay out of cloud sync. Each device mints its own
/// random `id` for the same calendar event and de-duplicates on `externalRef`, so
/// syncing them on `id` returns each event to its origin device as a second copy.
final class ExternallyManagedItemTests: XCTestCase {

    func testCalendarBackedEventIsExcluded() {
        let event = EventItem(
            title: "Standup",
            anchor: .timeBlock(start: .now, end: .now.addingTimeInterval(1800)),
            externalRef: ExternalRef(source: .eventKit, identifier: "ek-123")
        )
        XCTAssertTrue(CloudSyncService.isExternallyManagedItem(event),
                      "A calendar mirror must not sync — it already arrives via the shared calendar")
    }

    func testEventKitReminderIsExcluded() {
        let reminder = ReminderItem(
            title: "Pick up parcel",
            anchor: .dueAt(.now),
            externalRef: ExternalRef(source: .eventKit, identifier: "ek-456")
        )
        XCTAssertTrue(CloudSyncService.isExternallyManagedItem(reminder))
    }

    /// An event the user created inside LEO has no external owner, so it only
    /// reaches other devices through cloud sync. Excluding it would lose data.
    func testNativeEventStillSyncs() {
        let native = EventItem(
            title: "Dinner with Sam",
            anchor: .timeBlock(start: .now, end: .now.addingTimeInterval(3600))
        )
        XCTAssertFalse(CloudSyncService.isExternallyManagedItem(native),
                       "A LEO-native event has no other channel — it must sync")
    }

    func testWorkoutAndMealAlwaysSync() {
        let workout = WorkoutItem(title: "Push day", anchor: .dueAt(.now))
        let meal = MealItem(title: "Oats", anchor: .dueAt(.now), recipeID: "oats-01")
        XCTAssertFalse(CloudSyncService.isExternallyManagedItem(workout))
        XCTAssertFalse(CloudSyncService.isExternallyManagedItem(meal))
    }
}

/// `habitInstance` is a valid `kind` in the schema and a real `Item` conformer, but
/// it was missing from the sync payload switch — habit check-ins, and therefore
/// streaks, never left the device. This pins the round-trip that carries them.
final class HabitInstanceSyncPayloadTests: XCTestCase {

    func testCompletedCheckInSurvivesRoundTrip() throws {
        let habitID = UUID()
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let original = HabitInstanceItem(
            title: "Morning stretch",
            anchor: .dueAt(completedAt),
            completion: .completed(at: completedAt),   // the state a streak is built from
            habitID: habitID,
            targetDuration: .seconds(600)
        )

        let data = try JSONEncoder().encode(try SnapshotHabitInstance(from: original))
        let restored = try JSONDecoder().decode(SnapshotHabitInstance.self, from: data).toItem()

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.title, original.title)
        XCTAssertEqual(restored.habitID, habitID, "habitID links the check-in to its habit")
        XCTAssertEqual(restored.completion, .completed(at: completedAt), "completion carries the streak")
        XCTAssertEqual(restored.anchor, original.anchor)
        XCTAssertEqual(restored.targetDuration, original.targetDuration)
    }
}

#endif
