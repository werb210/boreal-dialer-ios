// BOREAL_DIALER_v901_WIDGET_NO_AUTODIAL
import XCTest
@testable import BorealDialer

final class WidgetNoAutodialV901Tests: XCTestCase {
    func testWidgetRowLinkFillsTheKeypadWithoutDialling() {
        let link = DialerDeepLinkParser.parse(URL(string: "borealdialer://call?phone=%2B14035551234&start=false")!)
        XCTAssertEqual(link, .phone("+14035551234", start: false))
    }

    func testAFreshCallLinkStillDials() {
        let now = Date()
        let link = DeepLinkCoordinator.settled(.phone("+14035551234", start: true), receivedAt: now.addingTimeInterval(-3), now: now)
        XCTAssertEqual(link, .phone("+14035551234", start: true))
    }

    func testACallLinkThatWaitedOnlyFillsTheNumber() {
        let now = Date()
        let stale = DeepLinkCoordinator.settled(.phone("+14035551234", start: true), receivedAt: now.addingTimeInterval(-60), now: now)
        XCTAssertEqual(stale, .phone("+14035551234", start: false))
        let unknown = DeepLinkCoordinator.settled(.phone("+14035551234", start: true), receivedAt: nil, now: now)
        XCTAssertEqual(unknown, .phone("+14035551234", start: false))
    }

    func testNewCallIsUnchanged() {
        XCTAssertEqual(DeepLinkCoordinator.settled(.newCall, receivedAt: nil), .newCall)
    }
}
