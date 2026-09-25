import XCTest
@testable import BorealDialer

// BOREAL_DIALER_BLOCK_v506_TEAM_LINK_PREVIEWS
final class TeamLinkPreviewV506Tests: XCTestCase {
    func testFindsTheFirstWebLink() {
        XCTAssertEqual(TeamLinkPreviews.firstLink(in: "see https://boreal.financial/rates thanks")?.absoluteString, "https://boreal.financial/rates")
        XCTAssertNil(TeamLinkPreviews.firstLink(in: "no link here"))
    }

    func testDecodesServerPreview() throws {
        let json = #"{"url":"https://boreal.financial/","ok":true,"title":"Boreal","description":null,"imageUrl":null,"siteName":"boreal.financial"}"#
        let p = try JSONDecoder().decode(TeamLinkPreviewData.self, from: Data(json.utf8))
        XCTAssertEqual(p.title, "Boreal")
        XCTAssertTrue(p.ok)
    }
}
