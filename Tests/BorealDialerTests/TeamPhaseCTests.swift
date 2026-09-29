// BOREAL_DIALER_TEAM_PHASE_C_v673
import XCTest
@testable import BorealDialer

final class TeamPhaseCTests: XCTestCase {
    func testCardKeysFromPortalLinks() {
        let id = "0f8fad5b-d9cb-469f-a165-70867728950e"
        let text = "see https://staff.boreal.financial/crm/contacts/\(id) and /applications/\(id.uppercased()) and /crm/contacts/\(id)"
        XCTAssertEqual(TeamCardRefs.keys(in: text), ["contact:\(id)", "application:\(id)"])
        XCTAssertEqual(TeamCardRefs.keys(in: "no links here"), [])
    }

    func testRemindTimes() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        guard let raw = TeamCardRefs.remindAt("1h", now: now), let when = ISO8601DateFormatter().date(from: raw) else {
            return XCTFail("no time")
        }
        XCTAssertEqual(when.timeIntervalSince(now), 3600, accuracy: 1)
        XCTAssertNil(TeamCardRefs.remindAt("save", now: now))
        guard let t = TeamCardRefs.remindAt("tomorrow", now: now), let nine = ISO8601DateFormatter().date(from: t) else {
            return XCTFail("no tomorrow")
        }
        XCTAssertEqual(Calendar.current.component(.hour, from: nine), 9)
    }
}
