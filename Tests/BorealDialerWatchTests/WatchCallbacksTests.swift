// BOREAL_DIALER_WATCH_CALLBACKS_v219
import XCTest
@testable import BorealDialerWatch

final class WatchCallbacksTests: XCTestCase {
    private func decode(_ json: String) throws -> WatchCallback {
        try JSONDecoder().decode(WatchCallback.self, from: Data(json.utf8))
    }

    func testDecodesTheServerPayload() throws {
        let c = try decode("""
        {"id":"abc","title":"Collect promised documents","dueAt":"2026-09-15T14:00:00Z",
         "overdue":false,"contactId":"c1","contactName":"Bill Clementi","number":"+16479854619"}
        """)
        XCTAssertEqual(c.contactName, "Bill Clementi")
        XCTAssertEqual(c.number, "+16479854619")
        XCTAssertFalse(c.overdue)
        XCTAssertNotNil(c.dueAt)
    }

    func testParsesFractionalSecondTimestamps() throws {
        let c = try decode(#"{"id":"a","title":"t","dueAt":"2026-09-15T14:00:00.123Z","number":"+15551234567"}"#)
        XCTAssertNotNil(c.dueAt)
    }

    /// A row with an unreadable date is still a call worth showing - it just
    /// loses its time label. Dropping it would understate what is owed.
    func testSurvivesAnUnparseableDate() throws {
        let c = try decode(#"{"id":"a","title":"t","dueAt":"not a date","number":"+15551234567"}"#)
        XCTAssertNil(c.dueAt)
        XCTAssertEqual(c.number, "+15551234567")
    }

    func testSurvivesAMissingOptionalField() throws {
        let c = try decode(#"{"id":"a","title":"t","number":"+15551234567"}"#)
        XCTAssertNil(c.contactName)
        XCTAssertFalse(c.overdue)
    }

    func testNeverThrowsOnAnEmptyObject() throws {
        // A decode failure here blanks the whole list; a defaulted row does not.
        let c = try decode("{}")
        XCTAssertEqual(c.number, "")
        XCTAssertEqual(c.title, "Call")
    }
}
