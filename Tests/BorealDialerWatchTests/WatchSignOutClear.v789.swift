// BOREAL_DIALER_LOGOUT_CLEAR_v789 - an iPhone sign-out clears the wrist.
import XCTest
@testable import BorealDialerWatch

final class WatchSignOutClearV789Tests: XCTestCase {
    func testClearRemovesTheComplicationSnapshot() {
        WatchFaceSync.publish(.init(status: "available", missedCalls: 4, tasksDue: 1))
        WatchFaceSync.clear()
        let defaults = UserDefaults(suiteName: WatchFaceSync.appGroup)
        XCTAssertNil(defaults?.string(forKey: "presence.status"))
        XCTAssertEqual(defaults?.integer(forKey: "calls.missed"), 0)
        XCTAssertEqual(defaults?.integer(forKey: "tasks.due"), 0)
        XCTAssertNil(defaults?.string(forKey: "meeting.next.title"))
    }

    func testClearMessageRoundTripsUnderItsOwnKey() {
        let payload = WatchPayload.encode(WatchClearMessage(), under: WatchPayload.clearKey)
        XCTAssertNotNil(WatchPayload.decode(WatchClearMessage.self, from: payload, key: WatchPayload.clearKey))
        XCTAssertNil(WatchPayload.decode(WatchEvent.self, from: payload, key: WatchPayload.eventKey))
    }
}
