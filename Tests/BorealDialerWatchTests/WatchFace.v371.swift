// BOREAL_DIALER_WATCH_FACE_v371
import XCTest
@testable import BorealDialerWatch

final class WatchFaceV371Tests: XCTestCase {
    func testFaceDecodesTheServerShape() throws {
        let json = #"{"status":"busy","missedCalls":3,"tasksDue":2,"asOf":"2026-09-21T18:00:00Z"}"#
        let face = try JSONDecoder().decode(WatchFaceSync.Face.self, from: Data(json.utf8))
        XCTAssertEqual(face, WatchFaceSync.Face(status: "busy", missedCalls: 3, tasksDue: 2))
    }

    func testPublishWritesTheKeysTheComplicationsRead() {
        WatchFaceSync.publish(.init(status: "available", missedCalls: 4, tasksDue: 1))
        let defaults = UserDefaults(suiteName: WatchFaceSync.appGroup)
        XCTAssertEqual(defaults?.string(forKey: "presence.status"), "available")
        XCTAssertEqual(defaults?.integer(forKey: "calls.missed"), 4)
        XCTAssertEqual(defaults?.integer(forKey: "tasks.due"), 1)
    }

    func testOnlyKnownComplicationLinksRoute() {
        XCTAssertEqual(WatchComplicationLink.target(for: URL(string: "borealwatch://dial")!), "dial")
        XCTAssertEqual(WatchComplicationLink.target(for: URL(string: "borealwatch://recents")!), "recents")
        XCTAssertNil(WatchComplicationLink.target(for: URL(string: "borealwatch://delete-everything")!))
        XCTAssertNil(WatchComplicationLink.target(for: URL(string: "https://dial")!))
    }
}
