import XCTest
@testable import LEO

final class DeterministicParserTests: XCTestCase {
    let parser = DeterministicParser()

    // MARK: - PRD canonical phrases

    func test_callMomEverySunday() async {
        let result = await parser.parse("call mom every Sunday at 6pm")
        XCTAssertNotNil(result.draft)
        XCTAssertTrue(result.confidence >= 0.5)
        // Should be reminder or task; should have point or dueAt anchor
        if let anchor = result.draft?.anchor {
            switch anchor {
            case .point, .dueAt: break
            default: XCTFail("Expected point or dueAt, got \(anchor)")
            }
        }
    }

    func test_draftReportByFriday() async {
        let result = await parser.parse("draft Q3 report by Friday")
        XCTAssertNotNil(result.draft)
        XCTAssertTrue(result.confidence >= 0.4)
        XCTAssertTrue(result.draft is TaskItem)
    }

    func test_wakeMeUp() async {
        let result = await parser.parse("wake me up at 6:30 tomorrow")
        XCTAssertNotNil(result.draft)
        XCTAssertTrue(result.draft is AlarmItem)
        if case .point(let d) = result.draft?.anchor {
            let cal = Calendar.current
            XCTAssertEqual(cal.component(.hour, from: d), 6)
            XCTAssertEqual(cal.component(.minute, from: d), 30)
        } else {
            XCTFail("Expected .point anchor")
        }
    }

    func test_gymMWF() async {
        let result = await parser.parse("gym MWF 7am for 1 hour")
        XCTAssertNotNil(result.draft)
        XCTAssertTrue(result.confidence >= 0.4)
    }

    func test_dentistAtLocation() async {
        let result = await parser.parse("dentist June 12 at 2pm at 401 Pine St")
        XCTAssertNotNil(result.draft)
        XCTAssertTrue(result.confidence >= 0.3)
    }

    // MARK: - Type detection

    func test_reminderPrefix() async {
        let result = await parser.parse("remind me to take medication at 8pm")
        XCTAssertTrue(result.draft is ReminderItem)
    }

    func test_alarmPrefix() async {
        let result = await parser.parse("alarm 7:30am")
        XCTAssertTrue(result.draft is AlarmItem)
    }

    func test_emptyInput() async {
        let result = await parser.parse("")
        XCTAssertNil(result.draft)
        XCTAssertEqual(result.confidence, 0)
    }

    func test_untitledGoesInbox() async {
        let result = await parser.parse("xyzzy")
        // No date, no type hint → low confidence → Inbox
        XCTAssertTrue(result.shouldDefaultToInbox || result.draft?.anchor.isUntimed == true)
    }

    // MARK: - Date parsing

    func test_tomorrow() async {
        let result = await parser.parse("call dentist tomorrow")
        XCTAssertNotNil(result.draft?.anchor.sortDate)
        let cal = Calendar.current
        if let d = result.draft?.anchor.sortDate {
            XCTAssertTrue(cal.isDateInTomorrow(d))
        }
    }

    func test_tonight() async {
        let result = await parser.parse("review slides tonight")
        if let d = result.draft?.anchor.sortDate {
            let cal = Calendar.current
            XCTAssertEqual(cal.component(.hour, from: d), 20)
        }
    }

    // MARK: - Performance

    func test_parsePerformance() async {
        let phrases = ["remind me to call mom at 6pm", "gym MWF 7am", "draft report by friday",
                       "wake me up tomorrow at 6:30am", "dentist next tuesday at 2pm"]
        let start = Date.now
        for phrase in phrases {
            _ = await parser.parse(phrase)
        }
        let elapsed = Date.now.timeIntervalSince(start)
        // 5 phrases should parse in well under 1 second (target: < 50ms each)
        XCTAssertLessThan(elapsed, 1.0, "Parser took \(elapsed)s for 5 phrases")
    }
}
