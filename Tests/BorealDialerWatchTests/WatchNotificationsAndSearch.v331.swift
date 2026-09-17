// BOREAL_DIALER_WATCH_NOTIFICATIONS_v331
import XCTest
@testable import BorealDialerWatch

final class WatchNotificationsAndSearchTests: XCTestCase {
    private func event(_ kind: WatchEventKind, callId: String, at seconds: TimeInterval) -> WatchEvent {
        WatchEvent(kind: kind, callId: callId, displayName: "", handle: "+15875551234",
                   preview: "", occurredAt: Date(timeIntervalSince1970: seconds))
    }

    func testEventsWithoutACallIdStillGetTheirOwnRow() {
        // A task, a meeting and a message all arrive with callId "". Keyed on
        // callId alone they were one row; the Notifications screen showed a
        // single entry, or nothing.
        let task = event(.task, callId: "", at: 100)
        let meeting = event(.meeting, callId: "", at: 200)
        let message = event(.newMessage, callId: "", at: 300)
        let ids = Set([task.rowId, meeting.rowId, message.rowId])
        XCTAssertEqual(ids.count, 3)
    }

    func testTwoCallsOfTheSameKindAreDistinct() {
        XCTAssertNotEqual(event(.missedCall, callId: "a", at: 1).rowId,
                          event(.missedCall, callId: "b", at: 1).rowId)
    }

    func testTheSameEventKeepsTheSameRowId() {
        // The store replaces an event in place when the kind and callId match,
        // so a stable id matters as much as a unique one.
        XCTAssertEqual(event(.incomingCall, callId: "x", at: 42).rowId,
                       event(.incomingCall, callId: "x", at: 42).rowId)
    }

    func testAnEventStillReadsAsSomethingWhenNoNameWasResolved() {
        XCTAssertEqual(event(.missedCall, callId: "x", at: 1).subtitle, "+15875551234")
    }
}
