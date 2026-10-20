import XCTest
@testable import BorealDialer

// BOREAL_DIALER_v830_DIALER_CONTROLS - extensions, participant status, the "won't receive calls" banner.
final class DialerV830Tests: XCTestCase {

    func testExtensionsAreSplitOffAndSentAsTones() {
        XCTAssertEqual(DialString.split("403-555-0142 ext. 123"), .init(number: "403-555-0142", extensionDigits: "123"))
        XCTAssertEqual(DialString.split("4035550142,123"), .init(number: "4035550142", extensionDigits: "123"))
        XCTAssertEqual(DialString.split("+1 403 555 0142 x 77"), .init(number: "+1 403 555 0142", extensionDigits: "77"))
        XCTAssertEqual(DialString.split("(403) 555-0142 extension 9#"), .init(number: "(403) 555-0142", extensionDigits: "9#"))
        XCTAssertEqual(DialString.split("4035550142#123"), .init(number: "4035550142", extensionDigits: "123"))
    }

    func testPlainNumbersAndShortCodesAreLeftAlone() {
        XCTAssertEqual(DialString.split("+14035550142"), .init(number: "+14035550142", extensionDigits: nil))
        XCTAssertEqual(DialString.split("*67 403"), .init(number: "*67 403", extensionDigits: nil))
        XCTAssertEqual(DialString.split("4035550142,"), .init(number: "4035550142", extensionDigits: nil))
    }

    func testParticipantStatusInWords() {
        XCTAssertEqual(ActiveCallControls.statusText("ringing"), "Ringing…")
        XCTAssertEqual(ActiveCallControls.statusText("pending_dial"), "Calling…")
        XCTAssertEqual(ActiveCallControls.statusText("busy"), "Busy")
        XCTAssertEqual(ActiveCallControls.statusText("no-answer"), "No answer")
        XCTAssertNil(ActiveCallControls.statusText("joined"))
    }

    func testBannerOnlyForALastingGapAndNeverDuringACall() {
        let now = Date()
        XCTAssertFalse(CallReadinessBanner.shouldShow(notReceivingSince: nil, callIdle: true, now: now))
        XCTAssertFalse(CallReadinessBanner.shouldShow(notReceivingSince: now.addingTimeInterval(-5), callIdle: true, now: now))
        XCTAssertTrue(CallReadinessBanner.shouldShow(notReceivingSince: now.addingTimeInterval(-30), callIdle: true, now: now))
        XCTAssertFalse(CallReadinessBanner.shouldShow(notReceivingSince: now.addingTimeInterval(-30), callIdle: false, now: now))
    }
}
