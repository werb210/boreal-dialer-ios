import XCTest
@testable import BorealDialer

final class CallDirectoryStoreTests: XCTestCase {
    func testConvertsE164ToCallKitPhoneNumber() {
        XCTAssertEqual(CallDirectoryStore.phoneNumber(fromE164: "+14155550123"), 1_415_555_0123)
        XCTAssertEqual(CallDirectoryStore.phoneNumber(fromE164: " +442071838750 \n"), 44_207_183_8750)
    }

    func testRejectsNumbersThatAreNotE164() {
        XCTAssertNil(CallDirectoryStore.phoneNumber(fromE164: "4155550123"))
        XCTAssertNil(CallDirectoryStore.phoneNumber(fromE164: "+1 (415) 555-0123"))
        XCTAssertNil(CallDirectoryStore.phoneNumber(fromE164: "+"))
        XCTAssertNil(CallDirectoryStore.phoneNumber(fromE164: "+0"))
    }
}
