// BOREAL_DIALER_TESTS_v40
// The repo had no test target at all. Every bug that reached the simulator today
// was one of two kinds: a decode that failed on a real payload, or a request
// pointed at a route that does not exist. These cover the first kind directly
// and the second by pinning the paths.
import XCTest
@testable import BorealDialer

final class DecodingTests: XCTestCase {
    // node-postgres serialises bigint as a STRING to avoid losing precision past
    // 2^53, so any count(*) that is not cast ::int arrives as "2". This took out
    // the whole SMS tab behind a generic "could not load".
    func testUnreadCountDecodesFromString() throws {
        let json = """
        {"thread_key":"t1","contact_id":null,"display_name":"Jordan Mills",
         "phone":"+15875550142","last_at":null,"last_body":"hi","unread_count":"3"}
        """.data(using: .utf8)!
        let thread = try JSONDecoder().decode(SMSThread.self, from: json)
        XCTAssertEqual(thread.unread, 3)
    }

    func testUnreadCountDecodesFromNumber() throws {
        let json = """
        {"thread_key":"t1","unread_count":3}
        """.data(using: .utf8)!
        let thread = try JSONDecoder().decode(SMSThread.self, from: json)
        XCTAssertEqual(thread.unread, 3)
    }

    // A missing count must not fail the whole array.
    func testMissingUnreadCountIsNotAnError() throws {
        let json = #"{"thread_key":"t1"}"#.data(using: .utf8)!
        let thread = try JSONDecoder().decode(SMSThread.self, from: json)
        XCTAssertEqual(thread.unread, 0)
    }

    func testContactFallsBackThroughNameFields() throws {
        let json = """
        {"id":"c1","name":null,"first_name":"Sat","last_name":"Grewal",
         "email":null,"phone":"+14035550142","company_name":"TFG","lead_status":"New"}
        """.data(using: .utf8)!
        let contact = try JSONDecoder().decode(CRMContact.self, from: json)
        XCTAssertEqual(contact.displayName, "Sat Grewal")
    }

    func testContactWithNoNameAtAllStillRenders() throws {
        let json = #"{"id":"c1","phone":"+14035550142"}"#.data(using: .utf8)!
        let contact = try JSONDecoder().decode(CRMContact.self, from: json)
        XCTAssertFalse(contact.displayName.isEmpty)
    }
}

final class FormattingTests: XCTestCase {
    func testE164FormatsAsNationalNumber() {
        XCTAssertEqual(PhoneFormat.display("+14035550142"), "(403) 555-0142")
        XCTAssertEqual(PhoneFormat.display("4035550142"), "(403) 555-0142")
    }

    // Anything that is not a North American number is left alone rather than
    // mangled into a shape it does not have.
    func testUnrecognisedNumbersAreLeftUntouched() {
        XCTAssertEqual(PhoneFormat.display("+442071838750"), "+442071838750")
        XCTAssertEqual(PhoneFormat.display(nil), "")
    }

    func testInitialsAreTakenFromTheFirstTwoWords() {
        XCTAssertEqual(AvatarCircle(name: "Andrew Polturak").initialsForTesting, "AP")
        XCTAssertEqual(AvatarCircle(name: "Boreal").initialsForTesting, "B")
    }
}
