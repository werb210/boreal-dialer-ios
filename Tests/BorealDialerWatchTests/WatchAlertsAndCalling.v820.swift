// BOREAL_DIALER_v820_WATCH
import XCTest
import UserNotifications
@testable import BorealDialerWatch

final class WatchAlertsAndCallingV820Tests: XCTestCase {
    // Mirrored iPhone alerts use the Watch app's category when it registers one, so all five must be here with the
    // same actions as the iPhone.
    func testTheWatchRegistersEveryIPhoneAlertCategory() {
        let byId = Dictionary(uniqueKeysWithValues: WatchNotificationRegistration.categories().map { ($0.identifier, $0) })
        for id in ["MESSAGE", "TASK", "MEETING", "MISSED_CALL", "VOICEMAIL", "CLIENT_MESSAGE", "SMS", "HANDOFF"] {
            XCTAssertNotNil(byId[id], "missing category \(id)")
        }
        XCTAssertEqual(byId["MISSED_CALL"]?.actions.map(\.identifier), ["CALL_BACK"])
        XCTAssertEqual(byId["VOICEMAIL"]?.actions.map(\.identifier), ["CALL_BACK"])
        // BOREAL_DIALER_v821 - the Watch adds "Quick reply" after the shared Reply on reply-able alerts.
        XCTAssertEqual(byId["SMS"]?.actions.map(\.identifier), ["REPLY", "QUICK_REPLY"])
        XCTAssertTrue(byId["HANDOFF"]?.actions.first is UNTextInputNotificationAction)
    }

    func testCompanionErrorsReadAsTheirCause() {
        XCTAssertEqual(WatchServiceError.companionRefused(reason: "signed_out").safeMessage,
                       "Sign in to Boreal Dialer on your iPhone.")
        XCTAssertTrue(WatchServiceError.server(code: "callback_not_verified", message: "").safeMessage
            .contains("Sign in to Boreal Dialer on your iPhone with the text code"))
    }

    func testPathChoice() {
        XCTAssertEqual(WatchCallPath.choose(companionReachable: true), .viaIPhone)
        XCTAssertEqual(WatchCallPath.choose(companionReachable: false), .serverCallback)
    }
}
