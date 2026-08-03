// BOREAL_DIALER_TEAM_ROSTER_SELF_v50
import XCTest
@testable import BorealDialer

final class TeamRosterTests: XCTestCase {
    private let roster = [
        TeamUser(id: "u1", name: "Todd Werboweski", email: "todd.w@boreal.financial"),
        TeamUser(id: "u2", name: "Andrew Polturak", email: "andrew.p@boreal.financial"),
        TeamUser(id: "u3", name: "client-submission", email: "client-submission@system.local")
    ]

    func testExcludesTheSignedInUser() {
        let members = TeamStore.rosterMembers(users: roster, excluding: "u1")
        XCTAssertFalse(members.contains { $0.id == "u1" })
        XCTAssertTrue(members.contains { $0.id == "u2" })
    }

    func testExcludesSystemAccounts() {
        let members = TeamStore.rosterMembers(users: roster, excluding: "u1")
        XCTAssertFalse(members.contains { $0.id == "u3" })
        XCTAssertEqual(members.count, 1)
    }

    // The JWT can fail to decode, in which case myId is nil. That must not
    // empty the roster - showing yourself is better than showing nobody.
    func testUnknownSelfStillListsEveryRealPerson() {
        let members = TeamStore.rosterMembers(users: roster, excluding: nil)
        XCTAssertEqual(members.map(\.id), ["u1", "u2"])
    }
}
