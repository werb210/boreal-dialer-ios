import XCTest
@testable import BorealDialer

// BOREAL_DIALER_SIRI_CALL_CLIENT_v320
final class SiriCallClientV320Tests: XCTestCase {
    private func contact(_ name: String, phone: String?, company: String? = nil) throws -> CRMContact {
        var json: [String: Any] = ["id": UUID().uuidString, "name": name]
        if let phone { json["phone"] = phone }
        if let company { json["company_name"] = company }
        return try JSONDecoder().decode(CRMContact.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testPhonesAreNormalisedForCalling() {
        XCTAssertEqual(BorealClientLookup.e164("(780) 916-7413"), "+17809167413")
        XCTAssertEqual(BorealClientLookup.e164("1-780-916-7413"), "+17809167413")
        XCTAssertEqual(BorealClientLookup.e164("+44 20 7946 0958"), "+442079460958")
        XCTAssertNil(BorealClientLookup.e164("916-7413"))
        XCTAssertNil(BorealClientLookup.e164(nil))
    }

    func testExactNameWinsAndContactsWithoutPhonesAreSkipped() throws {
        let list = [
            try contact("Tanya Vosser", phone: "7805550000"),
            try contact("Tanya Voss", phone: nil),
            try contact("Tanya Voss", phone: "7809167413"),
        ]
        XCTAssertEqual(BorealClientLookup.best(list, for: "tanya voss")?.callablePhone, "7809167413")
    }

    func testCallLinkIsUnderstoodByTheDialer() throws {
        let url = try XCTUnwrap(BorealClientLookup.callURL(phone: "+17809167413"))
        XCTAssertEqual(DialerDeepLinkParser.parse(url), .phone("+17809167413", start: true))
    }
}
