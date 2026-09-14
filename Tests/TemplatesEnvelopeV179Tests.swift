// BOREAL_DIALER_TEMPLATES_ITEMS_v179
import XCTest
@testable import BorealDialer

final class TemplatesEnvelopeV179Tests: XCTestCase {
    private func decode(_ json: String) throws -> [SMSTemplate] {
        try JSONDecoder().decode(TemplateLibraryEnvelope.self, from: Data(json.utf8)).templates
    }

    func testDecodesItemsKeyReturnedByTheServer() throws {
        let json = """
        {"items":[{"id":"a1","name":"Intro","body_text":"Hi","is_snippet":false}]}
        """
        let out = try decode(json)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.name, "Intro")
        XCTAssertEqual(out.first?.bodyText, "Hi")
    }

    func testStillDecodesTemplatesKeyFromTheWatchRoute() throws {
        let json = """
        {"templates":[{"id":"a1","name":"Intro","body_text":"Hi"}]}
        """
        XCTAssertEqual(try decode(json).count, 1)
    }

    func testStillDecodesABareArray() throws {
        XCTAssertEqual(try decode("""
        [{"id":"a1","name":"Intro","body_text":"Hi"}]
        """).count, 1)
    }

    func testNullBodyTextDoesNotFailTheWholeList() throws {
        let json = """
        {"items":[{"id":"a1","name":"HtmlOnly","body_text":null,"body_html":"<p>x</p>"}]}
        """
        let out = try decode(json)
        XCTAssertEqual(out.first?.bodyText, "")
        XCTAssertEqual(out.first?.isSnippet, false)
    }
}
