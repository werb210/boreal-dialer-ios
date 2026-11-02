// BOREAL_DIALER_v877_NO_NUMBER_CALL - never place a call with no number and no conference.
import XCTest
@testable import BorealDialer

final class NoNumberCallV877Tests: XCTestCase {
    func testANumberOrAConferenceIsNeeded() {
        XCTAssertTrue(TwilioVoiceManager.hasCallTarget(dialled: "+14035550100", conferenceFriendly: nil))
        XCTAssertTrue(TwilioVoiceManager.hasCallTarget(dialled: "", conferenceFriendly: "conf-1"))
        XCTAssertFalse(TwilioVoiceManager.hasCallTarget(dialled: "", conferenceFriendly: nil))
        XCTAssertFalse(TwilioVoiceManager.hasCallTarget(dialled: " ", conferenceFriendly: ""))
    }
}
