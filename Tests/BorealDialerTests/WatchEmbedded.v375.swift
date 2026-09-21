// BOREAL_DIALER_EMBED_WATCH_v375
// BOREAL_DIALER_EMBED_TEST_v380 - read the BorealDialer TARGET, not the scheme.
// project.yml has "  BorealDialer:" twice: once under schemes: (line ~30) and
// once under targets: (line ~44). The v375 test took the first one, the scheme,
// which has no dependencies, so it failed even though the build log shows
// BorealDialer.app/Watch/BorealDialerWatch.app being embedded.
import XCTest

final class WatchEmbeddedV375Tests: XCTestCase {
    private func phoneTargetLines() throws -> [String] {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { dir.deleteLastPathComponent() }
        let spec = try String(contentsOf: dir.appendingPathComponent("project.yml"), encoding: .utf8)
        let lines = spec.components(separatedBy: "\n")
        guard let targets = lines.firstIndex(of: "targets:") else {
            XCTFail("project.yml has no targets: section"); return []
        }
        guard let phone = lines[(targets + 1)...].firstIndex(of: "  BorealDialer:") else {
            XCTFail("targets: has no BorealDialer target"); return []
        }
        var block: [String] = []
        for line in lines[(phone + 1)...] {
            if line.isEmpty { block.append(line); continue }
            let indent = line.prefix(while: { $0 == " " }).count
            if indent <= 2 { break } // next target, or next top-level section
            block.append(line)
        }
        return block
    }

    func testTheIPhoneAppEmbedsTheWatchApp() throws {
        let block = try phoneTargetLines()
        XCTAssertTrue(
            block.contains { $0.trimmingCharacters(in: .whitespaces) == "- target: BorealDialerWatch" },
            "The BorealDialer target must depend on BorealDialerWatch so the Watch app is embedded"
        )
    }

    func testTheSchemeIsNotMistakenForTheTarget() throws {
        // The target block carries the bundle id; the scheme block never does.
        let block = try phoneTargetLines()
        XCTAssertTrue(block.contains { $0.contains("PRODUCT_BUNDLE_IDENTIFIER: financial.boreal.dialer") })
    }
}
