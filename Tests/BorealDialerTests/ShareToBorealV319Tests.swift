import XCTest
@testable import BorealDialer

// BOREAL_DIALER_SHARE_TO_BOREAL_v319
final class ShareToBorealV319Tests: XCTestCase {
    func testMimeTypesFollowTheFileExtension() {
        XCTAssertEqual(SharedFile(url: URL(fileURLWithPath: "/tmp/June.PDF")).mimeType, "application/pdf")
        XCTAssertEqual(SharedFile(url: URL(fileURLWithPath: "/tmp/AR.numbers")).mimeType, "application/vnd.apple.numbers")
        XCTAssertEqual(SharedFile(url: URL(fileURLWithPath: "/tmp/id.heic")).mimeType, "image/heic")
    }

    func testMultipartBodyCarriesTheApplicationCategoryAndFile() {
        let file = SharedFile(url: URL(fileURLWithPath: "/tmp/June.pdf"))
        let body = SharedDocumentInbox.multipartBody(applicationId: "app-1", category: "A/R", file: file, fileData: Data("PDF".utf8), boundary: "B1")
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"applicationId\"\r\n\r\napp-1\r\n"))
        XCTAssertTrue(text.contains("name=\"category\"\r\n\r\nA/R\r\n"))
        XCTAssertTrue(text.contains("filename=\"June.pdf\"\r\nContent-Type: application/pdf\r\n\r\nPDF\r\n--B1--"))
    }

    func testApplicationLabel() {
        XCTAssertEqual(AttachDocumentSheet.applicationLabel(ContactApplicationRow(id: "467689d3-2008", stage: "documents_review")), "Application 467689d3 · Documents Review")
    }
}
