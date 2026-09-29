// BOREAL_DIALER_LARGE_WIDGET_v685
import XCTest
@testable import BorealDialer

final class DialerDashboardTests: XCTestCase {
    func testMissedMeansInboundAndNotAnswered() {
        XCTAssertTrue(DialerDashboardStore.missed(direction: "inbound", status: "no-answer"))
        XCTAssertTrue(DialerDashboardStore.missed(direction: "Inbound", status: "busy"))
        XCTAssertFalse(DialerDashboardStore.missed(direction: "inbound", status: "completed"))
        XCTAssertFalse(DialerDashboardStore.missed(direction: "outbound", status: "no-answer"))
    }

    func testServerDatesWithAndWithoutFractions() {
        XCTAssertNotNil(DialerDashboardStore.date("2026-09-29T15:04:05.123Z"))
        XCTAssertNotNil(DialerDashboardStore.date("2026-09-29T15:04:05Z"))
        XCTAssertNil(DialerDashboardStore.date("not a date"))
        XCTAssertNil(DialerDashboardStore.date(nil))
    }
}
