// BOREAL_DIALER_BI_ACTIVITY_v52
// Payload transcribed from bi-server src/routes/biOutreachCrmRoutes.ts - the
// SELECT column list for GET /crm/outreach/contacts/:id/activity and its
// { ok, events } envelope.
import XCTest
@testable import BorealDialer

final class BIActivityTests: XCTestCase {
    private func decode(_ json: String) throws -> [TimelineEntry] {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(BIActivityEnvelope.self, from: data).events.map(\.asTimelineEntry)
    }

    func testCombinesEventTypeAndOutcomeIntoTheHeading() throws {
        let entries = try decode("""
        {"ok":true,"events":[
          {"id":"a1","contact_id":"bc1","actor_id":"u1","actor_name":"Todd Werboweski",
           "event_type":"call","outcome":"connected","body":"Walked through the PG cover.",
           "meta":null,"created_at":"2026-07-30T18:02:00Z"}]}
        """)
        XCTAssertEqual(entries[0].heading, "Call · connected")
        XCTAssertEqual(entries[0].body, "Walked through the PG cover.")
        XCTAssertEqual(entries[0].icon, "phone.fill")
    }

    func testFallsBackToTheEventTypeWhenThereIsNoOutcome() throws {
        let entries = try decode("""
        {"ok":true,"events":[
          {"id":"a2","event_type":"note","outcome":null,"body":"Left a message.",
           "actor_name":null,"created_at":"2026-07-29T15:00:00Z"}]}
        """)
        XCTAssertEqual(entries[0].heading, "Note")
    }

    func testSmsAndDemoGetTheirOwnIcons() throws {
        let entries = try decode("""
        {"ok":true,"events":[
          {"id":"a3","event_type":"sms","created_at":"2026-07-29T15:00:00Z"},
          {"id":"a4","event_type":"demo","created_at":"2026-07-28T15:00:00Z"}]}
        """)
        XCTAssertEqual(entries[0].icon, "message.fill")
        XCTAssertEqual(entries[1].icon, "person.2.fill")
    }

    // An unrecognised event type must still render rather than throw.
    // BOREAL_DIALER_BI_EVENT_LABEL_v54 - this previously expected
    // "Promoted_to_lender", which is not what .capitalized produces: Foundation
    // treats "_" as a word boundary and returns "Promoted_To_Lender". The
    // underscores are now stripped before capitalising.
    func testUnknownEventTypeStillDecodes() throws {
        let entries = try decode("""
        {"ok":true,"events":[{"id":"a5","event_type":"promoted_to_lender"}]}
        """)
        XCTAssertEqual(entries[0].heading, "Promoted To Lender")
        XCTAssertEqual(entries[0].icon, "circle")
        XCTAssertEqual(entries[0].timeLabel, "")
    }

    func testMultiWordEventTypeKeepsItsOutcome() throws {
        let entries = try decode("""
        {"ok":true,"events":[{"id":"a6","event_type":"status_change","outcome":"qualified"}]}
        """)
        XCTAssertEqual(entries[0].heading, "Status Change · qualified")
    }

    func testSingleWordEventTypeIsUnaffected() throws {
        let entries = try decode("""
        {"ok":true,"events":[{"id":"a7","event_type":"call","outcome":"connected"}]}
        """)
        XCTAssertEqual(entries[0].heading, "Call · connected")
    }
}
