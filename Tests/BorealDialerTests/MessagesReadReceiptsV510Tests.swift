import XCTest
@testable import BorealDialer

// BOREAL_DIALER_BLOCK_v510_MESSAGES_READ_RECEIPTS
final class MessagesReadReceiptsV510Tests: XCTestCase {
    func testUnreadStaffMessageSaysDelivered() throws {
        let json = #"{"id":"m1","senderType":"staff","body":"hi","createdAt":"2026-09-25T15:00:00Z"}"#
        let m = try JSONDecoder().decode(ThreadMessage.self, from: Data(json.utf8))
        XCTAssertNil(m.readAt)
        XCTAssertEqual(m.readLabel, "Delivered")
    }

    func testReadStaffMessageSaysRead() throws {
        let json = #"{"id":"m2","senderType":"staff","body":"hi","createdAt":"2026-09-25T15:00:00Z","readAt":"2026-09-25T15:05:00Z"}"#
        let m = try JSONDecoder().decode(ThreadMessage.self, from: Data(json.utf8))
        XCTAssertTrue(m.readLabel.hasPrefix("Read "))
        XCTAssertTrue(m.isOutbound)
    }

    // BOREAL_DIALER_v817_MESSAGING - the portal's /communications/messages-list row.
    func testConversationDecodesStringUnreadCount() throws {
        let json = #"{"thread_key":"c1","contact_id":"c1","display_name":"Jane Client","phone":"+15875550100","last_at":"2026-10-16T20:00:00Z","last_body":"Hello","unread_count":"2"}"#
        let c = try JSONDecoder().decode(MessageConversation.self, from: Data(json.utf8))
        XCTAssertEqual(c.unread, 2)
        XCTAssertEqual(c.title, "Jane Client")
        XCTAssertEqual(c.id, "c1")
    }
}
