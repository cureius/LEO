import XCTest
@testable import LEO

/// `ExternalRef.deterministicItemID` is the whole mechanism that makes it safe for
/// `SupabaseSync.push()` to upload EventKit-mirrored items at all — every device
/// mirroring the same real calendar event/reminder must compute the same id, or
/// pushing them duplicates the exact row the original push exclusion was added to
/// prevent (see SupabaseSync.swift's `isExternallyManagedItem` doc comment).
final class ExternalRefTests: XCTestCase {

    func test_sameSourceAndIdentifier_produceTheSameID() {
        let a = ExternalRef(source: .eventKit, identifier: "abc123")
        let b = ExternalRef(source: .eventKit, identifier: "abc123")
        XCTAssertEqual(a.deterministicItemID, b.deterministicItemID)
    }

    func test_differentIdentifiers_produceDifferentIDs() {
        let a = ExternalRef(source: .eventKit, identifier: "abc123")
        let b = ExternalRef(source: .eventKit, identifier: "xyz789")
        XCTAssertNotEqual(a.deterministicItemID, b.deterministicItemID)
    }

    /// Regression: `lastSeen` defaults to `.now` at construction — if the id ever
    /// hashed the whole struct instead of explicitly just source+identifier, this
    /// would silently break determinism (every construction gets a different id),
    /// with no compiler error or crash to catch it. This is the exact pitfall that
    /// makes the whole scheme not work if it regresses.
    func test_differingLastSeen_doesNotChangeTheID() {
        let a = ExternalRef(source: .eventKit, identifier: "abc123", lastSeen: .distantPast)
        let b = ExternalRef(source: .eventKit, identifier: "abc123", lastSeen: .distantFuture)
        XCTAssertEqual(a.deterministicItemID, b.deterministicItemID)
    }

    func test_isStableAcrossRepeatedCalls() {
        let ref = ExternalRef(source: .eventKit, identifier: "recurring-event/1737360000")
        let first = ref.deterministicItemID
        let second = ref.deterministicItemID
        XCTAssertEqual(first, second)
    }
}
