// BOREAL_DIALER_URL_TICKET_v790
import XCTest
@testable import BorealDialer

final class URLTicketV790Tests: XCTestCase {
    func testTeamSocketURLCarriesTheGivenCredential() {
        let url = URLTicket.teamSocketURL(token: "abc.def.ghi")
        XCTAssertEqual(url?.absoluteString, APIConfig.TEAM_WS_URL + "?token=abc.def.ghi")
    }

    func testTeamSocketURLPercentEncodesTheCredential() {
        let url = URLTicket.teamSocketURL(token: "a b")
        XCTAssertEqual(url?.absoluteString, APIConfig.TEAM_WS_URL + "?token=a%20b")
    }
}
