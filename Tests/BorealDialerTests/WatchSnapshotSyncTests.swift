// BOREAL_DIALER_WATCH_SNAPSHOT_WRITER_v210
import XCTest
@testable import BorealDialer

final class WatchSnapshotSyncTests: XCTestCase {
    private func decode(_ json: String) throws -> WatchSnapshot {
        try JSONDecoder().decode(WatchSnapshot.self, from: Data(json.utf8))
    }

    func testDecodesTheFullServerPayload() throws {
        let s = try decode(#"{"status":"available","missedCalls":3,"tasksDue":5}"#)
        XCTAssertEqual(s.status, "available")
        XCTAssertEqual(s.missedCalls, 3)
        XCTAssertEqual(s.tasksDue, 5)
    }

    /// A server older than v209 sends no tasksDue. That must not fail the whole
    /// decode and leave the complication showing stale values.
    func testToleratesAServerWithoutTasksDue() throws {
        let s = try decode(#"{"status":"busy","missedCalls":1}"#)
        XCTAssertEqual(s.status, "busy")
        XCTAssertEqual(s.missedCalls, 1)
        XCTAssertEqual(s.tasksDue, 0)
    }

    func testFallsBackToAwayRatherThanFailing() throws {
        let s = try decode(#"{}"#)
        XCTAssertEqual(s.status, "away")
        XCTAssertEqual(s.missedCalls, 0)
        XCTAssertEqual(s.tasksDue, 0)
    }

    /// The keys are a contract with BorealWatchWidget.swift. If either side is
    /// renamed alone the complication silently reverts to its fallbacks - which
    /// is exactly what happened before v210 existed.
    func testPublishUsesTheKeysTheComplicationReads() {
        let defaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroup)
        defaults?.removeObject(forKey: "presence.status")
        defaults?.removeObject(forKey: "calls.missed")
        defaults?.removeObject(forKey: "tasks.due")

        WatchSnapshotSync.publish(WatchSnapshot(status: "available", missedCalls: 2, tasksDue: 7))

        XCTAssertEqual(defaults?.string(forKey: "presence.status"), "available")
        XCTAssertEqual(defaults?.integer(forKey: "calls.missed"), 2)
        XCTAssertEqual(defaults?.integer(forKey: "tasks.due"), 7)
    }

    func testLastPublishedRoundTrips() {
        WatchSnapshotSync.publish(WatchSnapshot(status: "busy", missedCalls: 4, tasksDue: 1))
        let read = WatchSnapshotSync.lastPublished()
        XCTAssertEqual(read.status, "busy")
        XCTAssertEqual(read.missedCalls, 4)
        XCTAssertEqual(read.tasksDue, 1)
    }
}

// BOREAL_DIALER_WATCH_NEXT_MEETING_v211
extension WatchSnapshotSyncTests {
    func testPublishesAFutureMeeting() {
        let at = Date().addingTimeInterval(3600)
        WatchSnapshotSync.publishNextMeeting(title: "ABC Manufacturing", startsAt: at)
        let read = WatchSnapshotSync.nextMeeting()
        XCTAssertEqual(read?.title, "ABC Manufacturing")
        XCTAssertEqual(read?.startsAt.timeIntervalSince1970 ?? 0, at.timeIntervalSince1970, accuracy: 1)
    }

    /// A meeting that has already started must never sit on a watch face - it
    /// reads as the next thing due.
    func testRefusesToPublishAMeetingInThePast() {
        WatchSnapshotSync.publishNextMeeting(title: "Old", startsAt: Date().addingTimeInterval(-60))
        XCTAssertNil(WatchSnapshotSync.nextMeeting())
    }

    func testExpiresOnReadAsWellAsOnWrite() {
        // The face can render long after the phone last published.
        let defaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroup)
        defaults?.set("Stale", forKey: "meeting.next.title")
        defaults?.set(Date().addingTimeInterval(-300).timeIntervalSince1970, forKey: "meeting.next.at")
        XCTAssertNil(WatchSnapshotSync.nextMeeting())
    }

    func testClearsWhenThereIsNoMeeting() {
        WatchSnapshotSync.publishNextMeeting(title: "Something", startsAt: Date().addingTimeInterval(600))
        XCTAssertNotNil(WatchSnapshotSync.nextMeeting())
        WatchSnapshotSync.publishNextMeeting(title: nil, startsAt: nil)
        XCTAssertNil(WatchSnapshotSync.nextMeeting())
    }

    func testIgnoresABlankTitle() {
        WatchSnapshotSync.publishNextMeeting(title: "   ", startsAt: Date().addingTimeInterval(600))
        XCTAssertNil(WatchSnapshotSync.nextMeeting())
    }
}
