import XCTest
@testable import BorealDialer

// BOREAL_DIALER_WATCH_ENROLL_v146
final class WatchEnrollmentTests: XCTestCase {

    func testParsesAValidEightDigitCode() throws {
        let data = Data(#"{"oneTimeCode":"04817263","expiresAt":"2026-09-11T18:00:00Z"}"#.utf8)
        XCTAssertEqual(try WatchEnrollment.parse(data), "04817263")
    }

    func testKeepsLeadingZeros() throws {
        // The server zero-pads to 8; treating the code as a number would drop these.
        let data = Data(#"{"oneTimeCode":"00000042"}"#.utf8)
        XCTAssertEqual(try WatchEnrollment.parse(data), "00000042")
    }

    func testRejectsAShortCode() {
        let data = Data(#"{"oneTimeCode":"1234"}"#.utf8)
        XCTAssertThrowsError(try WatchEnrollment.parse(data))
    }

    func testRejectsANonNumericCode() {
        // The Watch's link() enforces the same rule; failing here gives a
        // clearer error than a silent link failure on the wrist.
        let data = Data(#"{"oneTimeCode":"ABCD1234"}"#.utf8)
        XCTAssertThrowsError(try WatchEnrollment.parse(data))
    }

    func testRejectsAMissingCode() {
        XCTAssertThrowsError(try WatchEnrollment.parse(Data(#"{"expiresAt":"x"}"#.utf8)))
    }

    func testRejectsJunk() {
        XCTAssertThrowsError(try WatchEnrollment.parse(Data("not json".utf8)))
    }

    @MainActor
    func testMintsOnFirstCall() {
        XCTAssertTrue(WatchEnrollment.shared.shouldMint(now: Date()))
    }
}
