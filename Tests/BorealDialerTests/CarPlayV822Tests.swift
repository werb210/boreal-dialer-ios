// BOREAL_DIALER_v822_CARPLAY - the CarPlay lists, starred favourites, the communication-notification sender and the
// Siri messaging rules: the pure logic behind each.
import XCTest
import Intents
@testable import BorealDialer

final class CarPlayRowsV822Tests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testRecentsCallBackTheNumberAndSkipWithheldOnes() throws {
        let calls = try decode([RecentCall].self, #"""
        [{"id":"1","direction":"inbound","status":"no-answer","phone_number":"+17809167413","contact_name":"Jane Client"},
         {"id":"2","direction":"outbound","status":"completed","phone_number":"403 555 0142","duration_seconds":75},
         {"id":"3","direction":"inbound","status":"completed","phone_number":null}]
        """#)
        let rows = CarPlayRows.recents(calls)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].title, "Jane Client")
        XCTAssertEqual(rows[0].symbol, "phone.down.fill")
        XCTAssertEqual(rows[0].action, .call(phone: "+17809167413"))
        XCTAssertTrue(rows[0].detail.hasPrefix("Missed"))
        XCTAssertEqual(rows[1].symbol, "phone.arrow.up.right")
        XCTAssertEqual(rows[1].action, .call(phone: "+14035550142"))
        XCTAssertEqual(rows[2].action, .notCallable)
    }

    func testListsStopAtTwentyFour() throws {
        let many = (0..<40).map { #"{"id":"\#($0)","direction":"outbound","phone_number":"+14035550142"}"# }
        let calls = try decode([RecentCall].self, "[" + many.joined(separator: ",") + "]")
        XCTAssertEqual(CarPlayRows.recents(calls).count, CarPlayRows.maxRows)
        XCTAssertEqual(CarPlayRows.maxRows, 24)
    }

    func testVoicemailRowsOpenTheVoicemail() throws {
        let items = try decode([Voicemail].self, #"[{"id":"vm1","contact_name":"Jane Client","contact_phone":"+17809167413","duration_seconds":34}]"#)
        let rows = CarPlayRows.voicemails(items)
        XCTAssertEqual(rows.first?.action, .voicemail(id: "vm1"))
        XCTAssertEqual(rows.first?.title, "Jane Client")
        XCTAssertTrue(rows.first?.detail.hasPrefix("0:34") ?? false)
    }

    func testFavouritesAreStarredClientsThenTeammates() throws {
        let team = try decode([QuickCallStaff].self, #"[{"userId":"u1","name":"Andrew","online":true}]"#)
        let clients = [FavouriteContact(id: "c1", name: "Jane Client", phone: "780-916-7413"),
                       FavouriteContact(id: "c2", name: "No Number", phone: "")]
        let rows = CarPlayRows.favourites(clients: clients, team: team)
        XCTAssertEqual(rows.map(\.title), ["Jane Client", "Andrew"])
        XCTAssertEqual(rows[0].action, .call(phone: "+17809167413"))
        XCTAssertEqual(rows[1].action, .callTeammate(userId: "u1", name: "Andrew"))
        XCTAssertEqual(rows[1].detail, "Team · online")
    }

    func testCallablePhone() {
        XCTAssertEqual(CarPlayRows.callablePhone("(780) 916-7413"), "+17809167413")
        XCTAssertNil(CarPlayRows.callablePhone("Anonymous"))
        XCTAssertNil(CarPlayRows.callablePhone("12"))
        XCTAssertNil(CarPlayRows.callablePhone(nil))
    }
}

final class FavouriteContactsV822Tests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "v822-favourites-\(UUID().uuidString)")
    }

    func testToggleAddsToTheTopAndRemoves() {
        let store = FavouriteContacts(defaults: defaults)
        XCTAssertTrue(store.toggle(id: "a", name: "A", phone: "+14035550001"))
        XCTAssertTrue(store.toggle(id: "b", name: "B", phone: "+14035550002"))
        XCTAssertEqual(store.all.map(\.id), ["b", "a"])
        XCTAssertFalse(store.toggle(id: "a", name: "A", phone: "+14035550001"))
        XCTAssertEqual(store.all.map(\.id), ["b"])
        XCTAssertTrue(store.contains("b"))
    }

    func testANumberIsRequiredAndTheListIsCapped() {
        let store = FavouriteContacts(defaults: defaults)
        XCTAssertFalse(store.toggle(id: "x", name: "X", phone: nil))
        XCTAssertFalse(store.toggle(id: "y", name: "Y", phone: "  "))
        for i in 0..<20 { store.toggle(id: "c\(i)", name: "C\(i)", phone: "+1403555\(String(format: "%04d", i))") }
        XCTAssertEqual(store.all.count, FavouriteContacts.limit)
        XCTAssertEqual(store.all.first?.id, "c19")
    }
}

final class CommunicationSenderV822Tests: XCTestCase {
    func testATextNamesItsSenderAndNumber() {
        let sender = CommunicationSender.from(
            userInfo: ["type": "sms", "phone": "+17809167413", "contactId": "c1", "senderName": " Jane   Client "],
            body: "Can you call me?", threadId: "sms:c1")
        XCTAssertEqual(sender, CommunicationSender(displayName: "Jane Client", handle: "+17809167413", isPhone: true,
                                                   contactId: "c1", conversationId: "sms:c1", body: "Can you call me?"))
    }

    func testAnUnknownTexterIsShownByNumber() {
        let sender = CommunicationSender.from(userInfo: ["type": "sms", "phone": "+17809167413"], body: "hi", threadId: "")
        XCTAssertEqual(sender?.displayName, "(780) 916-7413")
        XCTAssertEqual(sender?.conversationId, "sms:+17809167413")
    }

    func testAPortalMessageUsesTheContactHandle() {
        let sender = CommunicationSender.from(userInfo: ["type": "client_message", "contactId": "c9", "senderName": "Jane"],
                                              body: "Statements attached", threadId: "client_message:c9")
        XCTAssertEqual(sender?.handle, "boreal-contact:c9")
        XCTAssertEqual(sender?.isPhone, false)
        XCTAssertEqual(CommunicationSender.contactId(fromHandle: sender?.handle), "c9")
    }

    func testCallsAndVoicemailsAreNotMessages() {
        XCTAssertNil(CommunicationSender.from(userInfo: ["type": "missed_call", "phone": "+17809167413"], body: "x", threadId: ""))
        XCTAssertNil(CommunicationSender.from(userInfo: ["type": "voicemail", "phone": "+17809167413"], body: "x", threadId: ""))
        XCTAssertNil(CommunicationSender.from(userInfo: ["type": "sms"], body: "x", threadId: ""), "no number and no contact")
        XCTAssertNil(CommunicationSender.from(userInfo: ["type": "sms", "phone": "7809167413"], body: "x", threadId: ""))
    }
}

final class SiriMessageHandlerV822Tests: XCTestCase {
    func testAReplyGoesToTheNumberSiriWasGiven() {
        let person = INPerson(personHandle: INPersonHandle(value: "+17809167413", type: .phoneNumber), nameComponents: nil,
                              displayName: "Jane Client", image: nil, contactIdentifier: nil, customIdentifier: "c1")
        XCTAssertEqual(SiriMessageHandler.directTarget(person),
                       SiriMessageHandler.Target(phone: "+17809167413", name: "Jane Client", contactId: "c1"))
    }

    func testANameOnlyRecipientNeedsALookup() {
        let person = INPerson(personHandle: INPersonHandle(value: "boreal-contact:c1", type: .unknown), nameComponents: nil,
                              displayName: "Jane", image: nil, contactIdentifier: nil, customIdentifier: "c1")
        XCTAssertNil(SiriMessageHandler.directTarget(person))
    }

    func testLookupPrefersTheRepliedToContact() throws {
        let contacts = try JSONDecoder().decode([CRMContact].self, from: Data(#"""
        [{"id":"c1","name":"Jane A","phone":"780-916-7413"},
         {"id":"c2","name":"Jane B","phone":"+14035550142"},
         {"id":"c3","name":"Jane C","phone":null}]
        """#.utf8))
        XCTAssertEqual(SiriMessageHandler.targets(from: contacts, preferring: nil).map(\.contactId), ["c1", "c2"])
        XCTAssertEqual(SiriMessageHandler.targets(from: contacts, preferring: "c2").map(\.phone), ["+14035550142"])
    }
}
