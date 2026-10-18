// BOREAL_DIALER_v823 - widget / Control Center actions, action links, voice notes and business-card scanning:
// the pure logic behind each.
import XCTest
@testable import BorealDialer

final class StaffActionsV823Tests: XCTestCase {
    func testActionLinks() {
        XCTAssertEqual(StaffActionLink.parse(URL(string: "borealdialer://action/voice-note")!), .voiceNote)
        XCTAssertEqual(StaffActionLink.parse(URL(string: "borealdialer://action/next-follow-up")!), .nextFollowUp)
        XCTAssertNil(StaffActionLink.parse(URL(string: "borealdialer://action/delete-everything")!))
        XCTAssertNil(StaffActionLink.parse(URL(string: "borealdialer://action/voice-note?x=1")!))
        XCTAssertNil(StaffActionLink.parse(URL(string: "borealdialer://call?phone=%2B14035551234")!))
        XCTAssertNil(StaffActionLink.parse(URL(string: "https://boreal.financial/action/voice-note")!))
        // The call links are untouched by the new host.
        XCTAssertNil(DialerDeepLinkParser.parse(URL(string: "borealdialer://action/voice-note")!))
    }

    @MainActor
    func testPresenceAndTaskPaths() {
        XCTAssertEqual(StaffQuickActions.presenceStatus(busy: true), "busy")
        XCTAssertEqual(StaffQuickActions.presenceStatus(busy: false), "available")
        XCTAssertEqual(StaffQuickActions.completePath(taskId: "6f1c2a9e-1b2c-4d3e-8f90-123456789abc"),
                       "/tasks/6f1c2a9e-1b2c-4d3e-8f90-123456789abc/complete")
        XCTAssertNil(StaffQuickActions.completePath(taskId: "../users"))
        XCTAssertNil(StaffQuickActions.completePath(taskId: " "))
    }

    func testPendingActionsKeepTheLatestBusyChoiceAndEachTaskOnce() {
        StaffWidgetActionStore.clear()
        StaffWidgetActionStore.enqueue(.setBusy(true))
        StaffWidgetActionStore.enqueue(.completeTask(id: "t1"))
        StaffWidgetActionStore.enqueue(.completeTask(id: "t1"))
        StaffWidgetActionStore.enqueue(.setBusy(false))
        XCTAssertEqual(StaffWidgetActionStore.takePending(), [.completeTask(id: "t1"), .setBusy(false)])
        XCTAssertEqual(StaffWidgetActionStore.pending(), [])
        StaffWidgetActionStore.clear()
    }

    func testOldWidgetDashboardsStillDecode() throws {
        let old = Data(#"{"title":"Call Jane","detail":"9:00 AM","number":null}"#.utf8)
        let item = try JSONDecoder().decode(DashboardItem.self, from: old)
        XCTAssertNil(item.taskId)
        let new = DashboardItem(title: "Call Jane", detail: "9:00 AM", number: nil, taskId: "t9")
        XCTAssertEqual(try JSONDecoder().decode(DashboardItem.self, from: JSONEncoder().encode(new)).taskId, "t9")
    }
}

final class VoiceNotesV823Tests: XCTestCase {
    func testNotesPathAndText() {
        XCTAssertEqual(VoiceNoteAPI.notesPath(contactId: "c-123"), "/crm/contacts/c-123/notes")
        XCTAssertNil(VoiceNoteAPI.notesPath(contactId: "a/b"))
        XCTAssertEqual(VoiceNoteAPI.cleaned("  Sends statements Friday.\n"), "Sends statements Friday.")
    }

    func testTheNoteGoesToTheLastCallThatHasAClient() throws {
        let calls = try JSONDecoder().decode([RecentCall].self, from: Data(#"""
        [{"id":"1","direction":"outbound","phone_number":"+14035550142"},
         {"id":"2","direction":"inbound","phone_number":"+17809167413","contact_id":"c9","contact_name":"Jane Client"}]
        """#.utf8))
        XCTAssertEqual(VoiceNoteTarget.target(from: calls), VoiceNoteTarget(contactId: "c9", name: "Jane Client"))
        XCTAssertNil(VoiceNoteTarget.target(from: Array(calls.prefix(1))))
    }
}

final class BusinessCardV823Tests: XCTestCase {
    func testReadsATypicalCard() {
        let card = BusinessCardParser.parse([
            "NORTHWIND LOGISTICS INC.",
            "Jane Smith",
            "Chief Financial Officer",
            "T 780-555-0100",
            "Cell (403) 555-0142",
            "jane.smith@northwind.ca",
            "www.northwind.ca"
        ])
        XCTAssertEqual(card.firstName, "Jane")
        XCTAssertEqual(card.lastName, "Smith")
        XCTAssertEqual(card.company, "NORTHWIND LOGISTICS INC.")
        XCTAssertEqual(card.phone, "+14035550142")
        XCTAssertEqual(card.email, "jane.smith@northwind.ca")
    }

    func testLeavesUnknownFieldsEmpty() {
        let card = BusinessCardParser.parse(["Account Manager", "780-555-0100"])
        XCTAssertEqual(card.firstName, "")
        XCTAssertEqual(card.email, "")
        XCTAssertEqual(card.phone, "+17805550100")
    }

    // BOREAL_DIALER_v823b_CARD_PHONE
    func testPhonePatterns() {
        XCTAssertEqual(BusinessCardParser.phoneIn("T 780-555-0100"), "+17805550100")
        XCTAssertEqual(BusinessCardParser.phoneIn("Cell (403) 555-0142"), "+14035550142")
        XCTAssertEqual(BusinessCardParser.phoneIn("+1 403.555.0142"), "+14035550142")
        XCTAssertNil(BusinessCardParser.phoneIn("Suite 1200, 10180 101 St"))
        XCTAssertNil(BusinessCardParser.phoneIn("jane@northwind.ca"))
    }

    func testNameRules() {
        XCTAssertTrue(BusinessCardParser.isPersonName("Mary-Anne O'Neil"))
        XCTAssertFalse(BusinessCardParser.isPersonName("Sales Manager"))
        XCTAssertFalse(BusinessCardParser.isPersonName("jane smith"))
        XCTAssertFalse(BusinessCardParser.isPersonName("Boreal Capital Group"))
    }

    @MainActor
    func testScannedCompanyMatchesAnExistingOne() throws {
        let companies = try JSONDecoder().decode([CRMCompany].self, from: Data(#"[{"id":"k1","name":"Northwind Logistics Inc."}]"#.utf8))
        XCTAssertEqual(NewContactViewModel.matchCompany("NORTHWIND LOGISTICS INC", in: companies)?.id, "k1")
        XCTAssertNil(NewContactViewModel.matchCompany("Contoso", in: companies))
    }
}
