import XCTest
@testable import BorealDialer

// BOREAL_DIALER_BLOCK_v503_SMS_ATTACH_EVERYWHERE
final class SmsAttachEverywhereV503Tests: XCTestCase {
    func testUnreadablePhotoIsReported() {
        let result = SMSMediaLoader.photo(from: Data("not an image".utf8))
        XCTAssertNil(result.media)
        XCTAssertEqual(result.error, "Couldn't read that photo.")
    }

    func testMissingPdfIsReported() {
        let result = SMSMediaLoader.pdf(from: URL(fileURLWithPath: "/nonexistent/file.pdf"))
        XCTAssertNil(result.media)
        XCTAssertEqual(result.error, "Couldn't read that PDF.")
    }

    func testSmallPdfBecomesADataUrl() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("v503.pdf")
        try Data("%PDF-1.4".utf8).write(to: url)
        let result = SMSMediaLoader.pdf(from: url)
        XCTAssertEqual(result.media?.contentType, "application/pdf")
        XCTAssertTrue(result.media?.dataUrl.hasPrefix("data:application/pdf;base64,") ?? false)
    }
}
