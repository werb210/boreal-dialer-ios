// BOREAL_DIALER_WATCH_AUTOLINK_v341
import XCTest
@testable import BorealDialerWatch

final class WatchAutoLinkTests: XCTestCase {
    func testTheRequestKeyIsShared() {
        XCTAssertEqual(WatchPayload.enrollRequestKey, "boreal.watch.enroll.request")
    }

    func testTheEnrollPayloadStillRoundTrips() throws {
        let payload = WatchPayload.encode(WatchEnrollMessage(oneTimeCode: "12345678"), under: WatchPayload.enrollKey)
        let decoded = WatchPayload.decode(WatchEnrollMessage.self, from: payload, key: WatchPayload.enrollKey)
        XCTAssertEqual(decoded?.oneTimeCode, "12345678")
    }

    func testAStampedContextStillDecodes() throws {
        var payload = WatchPayload.encode(WatchEnrollMessage(oneTimeCode: "87654321"), under: WatchPayload.enrollKey)
        payload["boreal.watch.enroll.at"] = Date().timeIntervalSince1970
        let decoded = WatchPayload.decode(WatchEnrollMessage.self, from: payload, key: WatchPayload.enrollKey)
        XCTAssertEqual(decoded?.oneTimeCode, "87654321")
    }
}
