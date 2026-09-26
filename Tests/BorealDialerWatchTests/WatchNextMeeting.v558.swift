// BOREAL_DIALER_BLOCK_v558_WATCH_NEXT_MEETING
import XCTest
@testable import BorealDialerWatch

final class WatchNextMeetingV558Tests: XCTestCase {
    func testFaceDecodesTheMeeting() throws {
        let json = #"{"status":"available","missedCalls":0,"tasksDue":1,"nextMeeting":{"title":"ABC Manufacturing","startsAt":"2030-01-02T17:00:00.000Z"}}"#
        let face = try JSONDecoder().decode(WatchFaceSync.Face.self, from: Data(json.utf8))
        XCTAssertEqual(face.nextMeeting?.title, "ABC Manufacturing")
        XCTAssertNotNil(face.nextMeeting?.date)
    }

    func testOlderServerWithoutMeetingStillDecodes() throws {
        let json = #"{"status":"busy","missedCalls":3,"tasksDue":2,"nextMeeting":null}"#
        let face = try JSONDecoder().decode(WatchFaceSync.Face.self, from: Data(json.utf8))
        XCTAssertNil(face.nextMeeting)
    }

    func testPublishWritesAndClearsTheMeetingKeys() {
        let defaults = UserDefaults(suiteName: WatchFaceSync.appGroup)
        let future = WatchFaceSync.Meeting(title: "ABC Manufacturing", startsAt: "2030-01-02T17:00:00Z")
        WatchFaceSync.publish(.init(status: "available", missedCalls: 0, tasksDue: 0, nextMeeting: future))
        XCTAssertEqual(defaults?.string(forKey: "meeting.next.title"), "ABC Manufacturing")
        XCTAssertGreaterThan(defaults?.double(forKey: "meeting.next.at") ?? 0, 0)

        WatchFaceSync.publish(.init(status: "available", missedCalls: 0, tasksDue: 0))
        XCTAssertNil(defaults?.string(forKey: "meeting.next.title"))
    }
}
