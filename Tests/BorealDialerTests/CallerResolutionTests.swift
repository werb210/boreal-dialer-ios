// BOREAL_DIALER_RESOLVE_CALLER_CONTRACT_v45
import XCTest
@testable import BorealDialer

final class CallerResolutionTests: XCTestCase {
    func testDecodesAContactMatch() throws {
        let json = """
        {"ok":true,"matched":true,"isStaff":false,"name":"Sat Grewal",
         "contactId":"c1","companyName":"TFG Holdings",
         "applicationId":"a1","applicationName":"TFG expansion"}
        """.data(using: .utf8)!
        let resolved = try JSONDecoder().decode(ResolvedCaller.self, from: json)
        XCTAssertEqual(resolved.displayName, "Sat Grewal")
        XCTAssertEqual(resolved.company, "TFG Holdings")
        XCTAssertEqual(resolved.display, "Sat Grewal · TFG Holdings")
        XCTAssertEqual(resolved.contactId, "c1")
    }

    func testDecodesAnInternalStaffMatch() throws {
        let json = """
        {"ok":true,"matched":true,"isStaff":true,"name":"Andrew Polturak","userId":"u1"}
        """.data(using: .utf8)!
        let resolved = try JSONDecoder().decode(ResolvedCaller.self, from: json)
        XCTAssertEqual(resolved.isStaff, true)
        XCTAssertEqual(resolved.display, "Andrew Polturak")
        XCTAssertEqual(resolved.userId, "u1")
    }

    func testUnmatchedNumberHasNoDisplayName() throws {
        let json = """
        {"ok":true,"matched":false,"isStaff":false,"name":null}
        """.data(using: .utf8)!
        let resolved = try JSONDecoder().decode(ResolvedCaller.self, from: json)
        XCTAssertNil(resolved.displayName)
        XCTAssertNil(resolved.display)
    }

    func testBlankFieldsAreTreatedAsAbsent() throws {
        let json = """
        {"ok":true,"matched":true,"isStaff":false,"name":"  ","companyName":"  "}
        """.data(using: .utf8)!
        let resolved = try JSONDecoder().decode(ResolvedCaller.self, from: json)
        XCTAssertNil(resolved.displayName)
        XCTAssertNil(resolved.company)
    }

    func testLegacyEnvelopeYieldsNothing() throws {
        let json = """
        {"contact":{"contact_id":"c1","name":"Sat Grewal","company":"TFG"}}
        """.data(using: .utf8)!
        let resolved = try JSONDecoder().decode(ResolvedCaller.self, from: json)
        XCTAssertNil(resolved.displayName)
    }
}
