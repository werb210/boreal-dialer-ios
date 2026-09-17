import XCTest
@testable import BorealDialer

// BOREAL_DIALER_SESSION_GUARD_v314
final class SessionGuardV314Tests: XCTestCase {
    func testOnlyTheMainServerCanEndTheSession() {
        XCTAssertTrue(SessionGuard.isMainServer(URL(string: "https://server.boreal.financial/api/voice/token")!))
        XCTAssertFalse(SessionGuard.isMainServer(URL(string: APIConfig.BI_BASE_URL + "/crm/contacts")!))
    }

    func testSignOutReasonIsShownOnce() {
        SessionGuard.recordReason("test reason")
        XCTAssertEqual(SessionGuard.takeLastReason(), "test reason")
        XCTAssertNil(SessionGuard.takeLastReason())
    }

    func testWatchEnrollmentPathIsNotDoubled() throws {
        let request = try APIClient.shared.makeRequest(path: "/watch/auth/enrollment", method: "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://server.boreal.financial/api/watch/auth/enrollment")
    }
}
