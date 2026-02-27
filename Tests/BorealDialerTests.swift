import XCTest
@testable import BorealDialer

final class BorealDialerTests: XCTestCase {
    func testFetchMockToken() {
        XCTAssertEqual(NetworkManager.shared.fetchMockToken(), "MOCK_TWILIO_TOKEN")
    }
}
