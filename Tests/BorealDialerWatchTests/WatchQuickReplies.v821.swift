// BOREAL_DIALER_v821 - Watch quick replies: the extra notification action, who a reply goes to, and the shared ordering.
import XCTest
import UserNotifications
@testable import BorealDialerWatch

final class WatchQuickRepliesV821Tests: XCTestCase {
    func testQuickReplyIsAddedOnlyToReplyableAlerts() {
        XCTAssertEqual(WatchQuickReplyAction.category(for: .sms).actions.map(\.identifier), ["REPLY", "QUICK_REPLY"])
        XCTAssertEqual(WatchQuickReplyAction.category(for: .clientMessage).actions.map(\.identifier), ["REPLY", "QUICK_REPLY"])
        XCTAssertEqual(WatchQuickReplyAction.category(for: .voicemail).actions.map(\.identifier), ["CALL_BACK"])
        XCTAssertTrue(WatchQuickReplyAction.action().options.contains(.foreground), "it opens the reply list in the app")
    }

    func testReplyTargetFollowsTheAlert() throws {
        let sms = try XCTUnwrap(BorealAlertPayload(userInfo: ["type": "sms", "phone": "+14035550100", "contactId": "c1"]))
        XCTAssertEqual(WatchReplyTarget.from(payload: sms, name: "Tanya"),
                       .sms(phone: "+14035550100", contactId: "c1", name: "Tanya"))
        let portal = try XCTUnwrap(BorealAlertPayload(userInfo: ["type": "client_message", "contactId": "c2"]))
        XCTAssertEqual(WatchReplyTarget.from(payload: portal, name: " "), .portal(contactId: "c2", name: nil))
        let missed = try XCTUnwrap(BorealAlertPayload(userInfo: ["type": "missed_call", "phone": "+14035550100"]))
        XCTAssertNil(WatchReplyTarget.from(payload: missed, name: nil))
    }

    func testTheIPhoneRelayResolvesToTheSameTarget() throws {
        let relay = WatchReplyTarget.portal(contactId: "c2", name: "Walter").relayMessage(body: "On it")
        let payload = try XCTUnwrap(BorealAlertPayload(userInfo: relay.userInfo))
        XCTAssertEqual(BorealAlertReplyTarget.target(for: payload), .portalMessage(contactId: "c2"))
        let text = WatchReplyTarget.sms(phone: "+14035550100", contactId: nil, name: nil).relayMessage(body: "Hi")
        let smsPayload = try XCTUnwrap(BorealAlertPayload(userInfo: text.userInfo))
        XCTAssertEqual(BorealAlertReplyTarget.target(for: smsPayload), .sms(phone: "+14035550100", contactId: nil))
    }

    func testSnippetsComeFirstOnTheWrist() {
        let ordered = QuickReplyOrdering.ordered([
            QuickReply(id: "t", name: "Template", body: "T", isSnippet: false),
            QuickReply(id: "s", name: "Snippet", body: "S", isSnippet: true),
        ])
        XCTAssertEqual(ordered.map(\.id), ["s", "t"])
    }
}
