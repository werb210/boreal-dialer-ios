// BOREAL_DIALER_BI_CONTACTS_v51
import XCTest
@testable import BorealDialer

final class BIDirectoryTests: XCTestCase {
    func testContactMapsOntoTheSharedContactType() throws {
        let json = """
        {"status":"ok","total":1,"page":1,"pageSize":200,"data":[
          {"id":"bc1","full_name":"Priya Raman","first_name":"Priya","last_name":"Raman",
           "email":"priya@example.ca","phone_e164":"+14035550142","title":"CFO",
           "tags":["pgi"],"notes":null,"outreach_status":"engaged",
           "outreach_owner_id":"u1","company_id":"co1","company_name":"Raman Logistics",
           "created_at":"2026-07-01T12:00:00Z"}]}
        """.data(using: .utf8)!
        let rows = try JSONDecoder().decode(BIListEnvelope<BIContactRow>.self, from: json).data
        let contact = rows[0].asCRMContact
        XCTAssertEqual(contact.id, "bc1")
        XCTAssertEqual(contact.name, "Priya Raman")
        XCTAssertEqual(contact.phone, "+14035550142")
        XCTAssertEqual(contact.companyName, "Raman Logistics")
        XCTAssertEqual(contact.leadStatus, "engaged")
    }

    func testCompanyPrefersTheOperatingName() throws {
        let json = """
        {"status":"ok","data":[
          {"id":"co1","legal_name":"1234567 Alberta Ltd.","operating_name":"Raman Logistics",
           "business_number":"BN1","city":"Calgary","province":"AB","industry":"Transport",
           "owner_id":null,"tags":[],"created_at":"2026-07-01T12:00:00Z","contact_count":3}]}
        """.data(using: .utf8)!
        let rows = try JSONDecoder().decode(BIListEnvelope<BICompanyRow>.self, from: json).data
        let company = rows[0].asCRMCompany
        XCTAssertEqual(company.displayName, "Raman Logistics")
        XCTAssertEqual(company.subtitle, "Company · 3 contacts")
    }

    func testCompanyFallsBackToTheLegalName() throws {
        let json = """
        {"status":"ok","data":[
          {"id":"co2","legal_name":"Northwind Holdings Inc.","operating_name":"  ",
           "contact_count":1}]}
        """.data(using: .utf8)!
        let rows = try JSONDecoder().decode(BIListEnvelope<BICompanyRow>.self, from: json).data
        XCTAssertEqual(rows[0].asCRMCompany.displayName, "Northwind Holdings Inc.")
    }

    func testSparseContactStillDecodes() throws {
        let json = """
        {"status":"ok","data":[{"id":"bc2"}]}
        """.data(using: .utf8)!
        let rows = try JSONDecoder().decode(BIListEnvelope<BIContactRow>.self, from: json).data
        XCTAssertEqual(rows[0].asCRMContact.id, "bc2")
        XCTAssertNil(rows[0].asCRMContact.phone)
    }
}
