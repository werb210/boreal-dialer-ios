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

    // BOREAL_DIALER_WATCH_NAME_v56
    func testTheNamedCopyIsTheSameCallNotASecondOne() {
        let number = WatchEvent(kind: .incomingCall, callId: "call-1",
                                displayName: "", handle: "+15551234567")
        let named = WatchEvent(kind: .incomingCall, callId: "call-1",
                               displayName: "Gifford Lewis", handle: "+15551234567")
        XCTAssertEqual(number.callId, named.callId)
        XCTAssertEqual(number.kind, named.kind)
        // Not equal, so it is not dropped as a duplicate before it can update.
        XCTAssertNotEqual(number, named)
        XCTAssertEqual(number.subtitle, "+15551234567")
        XCTAssertEqual(named.subtitle, "Gifford Lewis")
    }

    func testAResolvedNameAndCompanyReadAsOneLine() {
        let event = WatchEvent(kind: .incomingCall, callId: "c",
                               displayName: "Gifford Lewis \u{00B7} Acme Ltd",
                               handle: "+15551234567")
        XCTAssertEqual(event.subtitle, "Gifford Lewis \u{00B7} Acme Ltd")
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

    func testNotificationRouterRejectsUnknownAndArbitraryURLPayloads() {
        if case .home = WatchNotificationRouter.route(userInfo: ["type": "unknown", "url": "https://evil.invalid"]) {} else { XCTFail() }
        if case .message(let id) = WatchNotificationRouter.route(userInfo: ["type": "client_message", "id": "https://evil.invalid"]) {
            XCTAssertNil(id)
        } else { XCTFail() }
    }

    func testNotificationCategoriesRouteToTypedDestinations() {
        if case .task("task-1") = WatchNotificationRouter.route(userInfo: ["type": "task", "id": "task-1"]) {} else { XCTFail() }
        if case .meeting("meeting_2") = WatchNotificationRouter.route(userInfo: ["type": "meeting", "id": "meeting_2"]) {} else { XCTFail() }
        if case .missedCall("call-3") = WatchNotificationRouter.route(userInfo: ["type": "missed_call", "id": "call-3"]) {} else { XCTFail() }
    }

    func testWatchPushRegistrationIsDistinctFromIOSRegistrations() {
        let watch = DeviceRegistration(deviceId: "watch", platform: .watchos, pushType: .standard, token: "watch-token")
        let phone = DeviceRegistration(deviceId: "phone", platform: .ios, pushType: .standard, token: "phone-token")
        let voip = DeviceRegistration(deviceId: "phone", platform: .ios, pushType: .voip, token: "voip-token")
        XCTAssertNotEqual(watch, phone); XCTAssertNotEqual(watch, voip); XCTAssertNotEqual(phone, voip)
    }

    func testPhoneNormalizationUsedByWatchDialer() {
        XCTAssertEqual(PhoneNumberNormalizer.normalize("(403) 555-1234"), "+14035551234")
        XCTAssertEqual(PhoneNumberNormalizer.normalize("+44 20 7946 0958"), "+442079460958")
        XCTAssertNil(PhoneNumberNormalizer.normalize("123"))
    }
}
