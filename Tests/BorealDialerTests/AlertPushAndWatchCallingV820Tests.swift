// BOREAL_DIALER_v820_WATCH - alert pushes (token upload, categories, tap routing, replies) and the Watch call path.
import XCTest
import UserNotifications
@testable import BorealDialer

final class PushTokenV820Tests: XCTestCase {
    func testEnvironmentFollowsTheBuildLikeTheWatchDoes() {
        XCTAssertEqual(PushTokenEnvironment.value(isDebug: true), "sandbox")
        XCTAssertEqual(PushTokenEnvironment.value(isDebug: false), "production")
#if DEBUG
        XCTAssertEqual(PushTokenEnvironment.current, "sandbox")
#else
        XCTAssertEqual(PushTokenEnvironment.current, "production")
#endif
    }

    func testTokenIsLowercaseHex() {
        XCTAssertEqual(PushTokenEnvironment.hex(Data([0x00, 0xAB, 0x10, 0xff])), "00ab10ff")
    }

    @MainActor
    func testRegisterBodyMatchesTheServerContract() throws {
        let body = StaffPushTokenRegistrar.registerBody(token: "abcd", environment: "sandbox")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: String])
        XCTAssertEqual(json, ["token": "abcd", "environment": "sandbox", "app": "dialer-ios"])
    }

    @MainActor
    func testUploadOnlyWhenNewOrStale() {
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertFalse(StaffPushTokenRegistrar.needsUpload(token: nil, lastUploadedToken: nil, lastUploadedAt: nil, now: now))
        XCTAssertTrue(StaffPushTokenRegistrar.needsUpload(token: "a", lastUploadedToken: nil, lastUploadedAt: nil, now: now))
        XCTAssertTrue(StaffPushTokenRegistrar.needsUpload(token: "b", lastUploadedToken: "a", lastUploadedAt: now, now: now))
        XCTAssertFalse(StaffPushTokenRegistrar.needsUpload(token: "a", lastUploadedToken: "a",
                                                           lastUploadedAt: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(StaffPushTokenRegistrar.needsUpload(token: "a", lastUploadedToken: "a",
                                                          lastUploadedAt: now.addingTimeInterval(-7 * 3600), now: now))
    }
}

final class AlertPayloadV820Tests: XCTestCase {
    func testTypeIsReadAndFieldsAreValidated() throws {
        let payload = try XCTUnwrap(BorealAlertPayload(userInfo: [
            "type": "sms", "phone": "403 555 0100", "contactId": "c_1-2", "threadKind": "SMS"
        ]))
        XCTAssertEqual(payload.kind, .sms)
        XCTAssertEqual(payload.phone, "+14035550100")
        XCTAssertEqual(payload.contactId, "c_1-2")
        XCTAssertEqual(payload.threadKind, "sms")
    }

    func testCategoryIsTheFallbackForAMissingType() {
        let payload = BorealAlertPayload(userInfo: ["aps": ["category": "VOICEMAIL"]])
        XCTAssertEqual(payload?.kind, .voicemail)
    }

    func testUnsafeValuesAreDropped() throws {
        let payload = try XCTUnwrap(BorealAlertPayload(userInfo: [
            "type": "client_message", "contactId": "../../admin", "phone": "call me"
        ]))
        XCTAssertNil(payload.contactId)
        XCTAssertNil(payload.phone)
        XCTAssertNil(BorealAlertPayload(userInfo: ["type": "stage_change"]))
    }

    func testCategoryIdsAreTheUppercasedTypes() {
        XCTAssertEqual(BorealAlertKind.allCases.map(\.categoryId),
                       ["MISSED_CALL", "VOICEMAIL", "CLIENT_MESSAGE", "SMS", "HANDOFF"])
    }
}

final class AlertCategoriesV820Tests: XCTestCase {
    func testEveryTypeHasACategoryWithTheRightAction() {
        let categories = Dictionary(uniqueKeysWithValues: BorealAlertCategories.all().map { ($0.identifier, $0) })
        XCTAssertEqual(Set(categories.keys), ["MISSED_CALL", "VOICEMAIL", "CLIENT_MESSAGE", "SMS", "HANDOFF"])
        for id in ["MISSED_CALL", "VOICEMAIL"] {
            XCTAssertEqual(categories[id]?.actions.map(\.identifier), ["CALL_BACK"])
            XCTAssertTrue(categories[id]?.actions.first?.options.contains(.foreground) ?? false)
        }
        for id in ["SMS", "CLIENT_MESSAGE", "HANDOFF"] {
            let action = categories[id]?.actions.first
            XCTAssertEqual(action?.identifier, "REPLY")
            XCTAssertTrue(action is UNTextInputNotificationAction)
            // Sent in the background, so it works from the lock screen and from the Watch.
            XCTAssertFalse(action?.options.contains(.foreground) ?? true)
        }
    }

    func testTheMissedCallCategoryIsStillTheV239One() {
        XCTAssertEqual(MissedCallNotification.category().identifier, "MISSED_CALL")
        XCTAssertEqual(MissedCallNotification.category().actions.map(\.identifier), ["CALL_BACK"])
    }

    func testVoicemailCallBackUsesTheDeepLinkPath() throws {
        let url = try XCTUnwrap(MissedCallNotification.callBackURL(userInfo: ["type": "voicemail", "phone": "+15875550100"]))
        XCTAssertEqual(DialerDeepLinkParser.parse(url), .phone("+15875550100", start: true))
        XCTAssertNil(MissedCallNotification.callBackURL(userInfo: ["type": "sms", "phone": "+15875550100"]))
    }
}

final class AlertDestinationV820Tests: XCTestCase {
    private func destination(_ info: [AnyHashable: Any]) -> AlertDestination? {
        AlertDestination.destination(userInfo: info)
    }

    func testEachTypeOpensItsTab() {
        XCTAssertEqual(destination(["type": "missed_call", "phone": "+15875550100"]), .calls)
        XCTAssertEqual(destination(["type": "voicemail"]), .voicemail)
        XCTAssertEqual(destination(["type": "sms", "phone": "+15875550100", "contactId": "c1"]),
                       .smsThread(phone: "+15875550100", contactId: "c1"))
        XCTAssertEqual(destination(["type": "client_message", "contactId": "c1"]), .messagesConversation(contactId: "c1"))
        XCTAssertEqual(destination(["type": "handoff", "contactId": "c1"]), .messagesConversation(contactId: "c1"))
        XCTAssertEqual(destination(["type": "client_message"]), .messages)
        XCTAssertNil(destination(["type": "stage_change"]))
    }

    func testAnSMSHandoffOpensTheSMSThread() {
        XCTAssertEqual(destination(["type": "handoff", "threadKind": "sms", "phone": "+15875550100", "contactId": "c1"]),
                       .smsThread(phone: "+15875550100", contactId: "c1"))
        XCTAssertEqual(destination(["type": "handoff", "threadKind": "messages", "phone": "+15875550100", "contactId": "c1"]),
                       .messagesConversation(contactId: "c1"))
    }

    func testTabs() {
        XCTAssertEqual(AlertDestination.calls.tab, .calls)
        XCTAssertEqual(AlertDestination.voicemail.tab, .calls)
        XCTAssertEqual(AlertDestination.smsThread(phone: nil, contactId: "c").tab, .sms)
        XCTAssertEqual(AlertDestination.messagesConversation(contactId: "c").tab, .messages)
    }

    func testReplyTargets() throws {
        let sms = try XCTUnwrap(BorealAlertPayload(userInfo: ["type": "sms", "phone": "+15875550100", "contactId": "c1"]))
        XCTAssertEqual(BorealAlertReplyTarget.target(for: sms), .sms(phone: "+15875550100", contactId: "c1"))
        let portal = try XCTUnwrap(BorealAlertPayload(userInfo: ["type": "client_message", "contactId": "c1", "phone": "+15875550100"]))
        XCTAssertEqual(BorealAlertReplyTarget.target(for: portal), .portalMessage(contactId: "c1"))
        let handoff = try XCTUnwrap(BorealAlertPayload(userInfo: ["type": "handoff", "threadKind": "sms", "phone": "+15875550100"]))
        XCTAssertEqual(BorealAlertReplyTarget.target(for: handoff), .sms(phone: "+15875550100", contactId: nil))
        let missed = try XCTUnwrap(BorealAlertPayload(userInfo: ["type": "missed_call", "phone": "+15875550100"]))
        XCTAssertNil(BorealAlertReplyTarget.target(for: missed))
        let noPhone = try XCTUnwrap(BorealAlertPayload(userInfo: ["type": "sms"]))
        XCTAssertNil(BorealAlertReplyTarget.target(for: noPhone))
    }

    func testAWatchRelayedReplyResolvesLikeThePush() throws {
        let relay = WatchAlertReplyMessage(kind: "handoff", contactId: "c1", phone: "+15875550100", threadKind: "sms", body: "On it")
        let payload = try XCTUnwrap(BorealAlertPayload(userInfo: relay.userInfo))
        XCTAssertEqual(BorealAlertReplyTarget.target(for: payload), .sms(phone: "+15875550100", contactId: "c1"))
        let encoded = WatchPayload.encode(relay, under: WatchPayload.alertReplyKey)
        XCTAssertEqual(WatchPayload.decode(WatchAlertReplyMessage.self, from: encoded, key: WatchPayload.alertReplyKey), relay)
    }
}

final class WatchCallPathV820Tests: XCTestCase {
    func testReachableIPhoneIsPreferred() {
        XCTAssertEqual(WatchCallPath.choose(companionReachable: true), .viaIPhone)
        XCTAssertEqual(WatchCallPath.choose(companionReachable: false), .serverCallback)
        XCTAssertEqual(WatchCallPath.viaIPhone.banner, "Calling via iPhone")
        XCTAssertEqual(WatchCallPath.serverCallback.banner, "Boreal will ring your Watch, press 1 to connect")
    }

    func testStatusLines() {
        XCTAssertEqual(WatchCallPath.statusText(.idle, path: nil), "")
        XCTAssertEqual(WatchCallPath.statusText(.requesting, path: .viaIPhone), "Asking your iPhone…")
        XCTAssertEqual(WatchCallPath.statusText(.ringing, path: .viaIPhone), "Calling… audio is on your iPhone or AirPods")
        XCTAssertEqual(WatchCallPath.statusText(.waitingForCallback, path: .serverCallback),
                       "Ringing your Watch… answer, then press 1")
        XCTAssertEqual(WatchCallPath.statusText(.connected, path: .serverCallback), "Connected. Hang up in the Phone app.")
        XCTAssertEqual(WatchCallPath.statusText(.ended, path: .serverCallback), "Call ended")
    }

    func testTheIPhoneOnlyPlacesCallsItCanPlace() {
        XCTAssertEqual(WatchPhoneCallDecision.evaluate(signedIn: true, idle: true, destination: "403-555-0100"),
                       .place("+14035550100"))
        XCTAssertEqual(WatchPhoneCallDecision.evaluate(signedIn: false, idle: true, destination: "+14035550100"),
                       .refuse("signed_out"))
        XCTAssertEqual(WatchPhoneCallDecision.evaluate(signedIn: true, idle: false, destination: "+14035550100"),
                       .refuse("busy"))
        XCTAssertEqual(WatchPhoneCallDecision.evaluate(signedIn: true, idle: true, destination: "12"),
                       .refuse("invalid_number"))
    }

    func testCallRequestAndReplySurviveTheSession() {
        let request = WatchPhoneCallRequest(destination: "+14035550100", contactId: "c1")
        let payload = WatchPayload.encode(request, under: WatchPayload.phoneCallKey)
        XCTAssertEqual(WatchPayload.decode(WatchPhoneCallRequest.self, from: payload, key: WatchPayload.phoneCallKey), request)
        let reply = WatchPhoneCallReply(accepted: false, reason: WatchPhoneCallReply.reasonBusy)
        let encoded = WatchPayload.encode(reply, under: WatchPayload.phoneCallReplyKey)
        XCTAssertEqual(WatchPayload.decode(WatchPhoneCallReply.self, from: encoded, key: WatchPayload.phoneCallReplyKey), reply)
        XCTAssertEqual(WatchPhoneCallReply.message(for: "busy"), "Your iPhone is already on a call.")
    }

    // The bridge must answer before the generic enroll/forward path swallows the message with an empty reply.
    func testTheBridgeAnswersCallRequestsFirst() throws {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { dir.deleteLastPathComponent() }
        let bridge = try String(contentsOf: dir.appendingPathComponent("Sources/Voice/WatchBridge.swift"), encoding: .utf8)
        let call = try XCTUnwrap(bridge.range(of: "WatchPhoneCallRequest.self"))
        let enroll = try XCTUnwrap(bridge.range(of: "message[WatchPayload.enrollRequestKey] != nil"))
        XCTAssertLessThan(call.lowerBound, enroll.lowerBound)
    }
}
