import XCTest
@testable import BorealDialer

// BOREAL_DIALER_BLOCK_v510_MESSAGES_READ_RECEIPTS
final class MessagesReadReceiptsV510Tests: XCTestCase {
    func testUnreadStaffMessageSaysDelivered() throws {
        let json = #"{"id":"m1","type":"chat","direction":"out","message":"hi","createdAt":"2026-09-25T15:00:00Z"}"#
        let m = try JSONDecoder().decode(ThreadMessage.self, from: Data(json.utf8))
        XCTAssertNil(m.readAt)
        XCTAssertEqual(m.readLabel, "Delivered")
    }

    func testReadStaffMessageSaysRead() throws {
        let json = #"{"id":"m2","type":"chat","direction":"out","message":"hi","createdAt":"2026-09-25T15:00:00Z","readAt":"2026-09-25T15:05:00Z"}"#
        let m = try JSONDecoder().decode(ThreadMessage.self, from: Data(json.utf8))
        XCTAssertTrue(m.readLabel.hasPrefix("Read "))
    }
}
