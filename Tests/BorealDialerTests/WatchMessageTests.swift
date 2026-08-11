// BOREAL_DIALER_WATCH_v55
import XCTest
@testable import BorealDialer

final class WatchMessageTests: XCTestCase {
    func testEventSurvivesTheRoundTripAcrossTheSession() {
        let event = WatchEvent(kind: .incomingCall, callId: "abc",
                               displayName: "Gifford Lewis", handle: "+15551234567")
        let payload = WatchPayload.encode(event, under: WatchPayload.eventKey)
        let decoded = WatchPayload.decode(WatchEvent.self, from: payload, key: WatchPayload.eventKey)
        XCTAssertEqual(decoded, event)
    }

    func testActionSurvivesTheRoundTrip() {
        let action = WatchActionMessage(action: .answer, callId: "abc")
        let payload = WatchPayload.encode(action, under: WatchPayload.actionKey)
        XCTAssertEqual(WatchPayload.decode(WatchActionMessage.self, from: payload,
                                           key: WatchPayload.actionKey), action)
    }

    func testAnUnknownCallerStillReadsAsSomethingDialable() {
        let event = WatchEvent(kind: .missedCall, callId: "x", displayName: "", handle: "+15550000000")
        XCTAssertEqual(event.subtitle, "+15550000000")
    }

    func testAResolvedNameWinsOverTheRawNumber() {
        let event = WatchEvent(kind: .newMessage, callId: "x",
                               displayName: "Andrew Polturak", handle: "+15550000000")
        XCTAssertEqual(event.subtitle, "Andrew Polturak")
    }

    func testGarbageIsRejectedRatherThanCrashingTheWrist() {
        XCTAssertNil(WatchPayload.decode(WatchEvent.self, from: [:], key: WatchPayload.eventKey))
        XCTAssertNil(WatchPayload.decode(WatchEvent.self, from: ["wrong": Data()],
                                         key: WatchPayload.eventKey))
    }

    func testEachKindCarriesItsOwnTitle() {
        XCTAssertEqual(WatchEvent(kind: .incomingCall, callId: "1", displayName: "", handle: "").title, "Incoming call")
        XCTAssertEqual(WatchEvent(kind: .missedCall, callId: "1", displayName: "", handle: "").title, "Missed call")
        XCTAssertEqual(WatchEvent(kind: .newMessage, callId: "1", displayName: "", handle: "").title, "New message")
    }
}
