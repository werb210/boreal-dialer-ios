// BOREAL_DIALER_READ_THIS_v687
import XCTest
@testable import BorealDialer

final class ReadThisV687Tests: XCTestCase {
    func testDecodesReadThisAndReceipts() throws {
        let json = """
        {"id":"m1","channel_id":"c1","sender_id":"todd","body":"Read the new form","created_at":null,"thread":null,"thread_root_id":null,"bot":null,
         "read_this":true,"read_by":[{"user_id":"andrew","read_at":"2026-10-07T20:00:00Z"}]}
        """.data(using: .utf8)!
        let m = try JSONDecoder().decode(TeamMessage.self, from: json)
        XCTAssertEqual(m.read_this, true)
        XCTAssertEqual(m.read_by?.first?.user_id, "andrew")
    }

    func testOrdinaryMessagesStillDecode() throws {
        let json = #"{"id":"m2","channel_id":"c1","sender_id":"todd","body":"hi"}"#.data(using: .utf8)!
        let m = try JSONDecoder().decode(TeamMessage.self, from: json)
        XCTAssertNil(m.read_this)
        XCTAssertNil(m.read_by)
    }

    func testSenderSeesWhoReadAndWhoIsWaiting() {
        let s = TeamStore.readThisSummary(readBy: [TeamReadReceipt(user_id: "andrew", read_at: nil)], memberIds: ["todd", "andrew", "caden"], senderId: "todd")
        XCTAssertEqual(s.read, ["andrew"])
        XCTAssertEqual(s.waiting, ["caden"])
    }
}
