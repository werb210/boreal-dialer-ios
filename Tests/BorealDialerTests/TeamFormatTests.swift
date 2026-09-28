// BOREAL_DIALER_TEAM_PHASE_B_v667
import XCTest
@testable import BorealDialer

final class TeamFormatTests: XCTestCase {
    private let fence = String(repeating: "\u{60}", count: 3)

    func testBulletsAndCodeFences() {
        let text = "hi\n- one\n* two\n" + fence + "\nlet a = 1\n" + fence + "\nbye"
        XCTAssertEqual(TeamFormat.blocks(text), [.line("hi"), .line("\u{2022} one"), .line("\u{2022} two"), .code("let a = 1"), .line("bye")])
    }

    func testOneLineCodeFence() {
        XCTAssertEqual(TeamFormat.blocks(fence + "x = 1" + fence), [.code("x = 1")])
    }

    func testSingleTildeStrikeBecomesMarkdown() {
        XCTAssertEqual(TeamFormat.markdownSource("~old~ and ~~kept~~"), "~~old~~ and ~~kept~~")
    }

    func testBoldIsParsedNotShownAsStars() {
        XCTAssertEqual(String(TeamFormat.attributed("**Big** news").characters), "Big news")
    }

    func testStatusClearTimes() {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 9
        parts.day = 28
        parts.hour = 14
        guard let now = Calendar.current.date(from: parts),
              let raw = TeamPhaseBStore.until("tomorrow8", now: now),
              let when = ISO8601DateFormatter().date(from: raw) else {
            return XCTFail("could not build the dates")
        }
        let got = Calendar.current.dateComponents([.day, .hour, .minute], from: when)
        XCTAssertEqual(got.day, 29)
        XCTAssertEqual(got.hour, 8)
        XCTAssertEqual(got.minute, 0)
        XCTAssertNil(TeamPhaseBStore.until("never", now: now))
    }
}
