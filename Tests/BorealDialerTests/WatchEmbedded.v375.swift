// BOREAL_DIALER_EMBED_WATCH_v375
import XCTest

final class WatchEmbeddedV375Tests: XCTestCase {
    func testTheIPhoneAppEmbedsTheWatchApp() throws {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { dir.deleteLastPathComponent() }
        let spec = try String(contentsOf: dir.appendingPathComponent("project.yml"), encoding: .utf8)
        let phone = spec.components(separatedBy: "\n  BorealDialer:\n").dropFirst().first ?? ""
        let phoneBlock = phone.components(separatedBy: "\n  BorealDialer").first ?? ""
        XCTAssertTrue(phoneBlock.contains("- target: BorealDialerWatch\n"))
    }
}
