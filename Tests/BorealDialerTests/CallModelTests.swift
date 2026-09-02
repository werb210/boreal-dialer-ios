import XCTest
@testable import BorealDialer

final class CallModelTests: XCTestCase {
    func testPhoneCallDirectionsRetainTheirWireValues() {
        XCTAssertEqual(CallDirection.inbound.rawValue, "inbound")
        XCTAssertEqual(CallDirection.outbound.rawValue, "outbound")
    }

    func testServerRecentCallDecodesAsThePhoneModel() throws {
        let json = Data(#"""
        {
          "id": "call-1",
          "direction": "inbound",
          "status": "completed",
          "duration_seconds": 42,
          "created_at": "2026-09-01T20:00:00Z",
          "phone_number": "+14035551234",
          "contact_id": "contact-1",
          "contact_name": "Test Contact"
        }
        """#.utf8)

        let call = try JSONDecoder().decode(RecentCall.self, from: json)
        XCTAssertEqual(call.id, "call-1")
        XCTAssertEqual(call.direction, "inbound")
        XCTAssertEqual(call.status, "completed")
        XCTAssertEqual(call.durationSeconds, 42)
        XCTAssertEqual(call.createdAt, "2026-09-01T20:00:00Z")
        XCTAssertEqual(call.phoneNumber, "+14035551234")
        XCTAssertEqual(call.contactId, "contact-1")
        XCTAssertEqual(call.contactName, "Test Contact")
    }
}
