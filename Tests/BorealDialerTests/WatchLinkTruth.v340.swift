// BOREAL_DIALER_WATCH_LINK_TRUTH_v340
import XCTest

final class WatchLinkTruthTests: XCTestCase {
    private func read(_ rel: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { dir.deleteLastPathComponent() }
        return try String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8)
    }

    func testDeliveryRequiresAPairedWatchWithTheAppInstalled() throws {
        // transferUserInfo is a silent no-op otherwise, which is exactly how the
        // code vanished while the phone reported success.
        let bridge = try read("Sources/Voice/WatchBridge.swift")
        XCTAssertTrue(bridge.contains("guard session.isPaired, session.isWatchAppInstalled else { return false }"))
    }

    func testTheSheetUsesTheReturnedValueInsteadOfAssumingSuccess() throws {
        let sheet = try read("UI/Settings/AccountSheet.swift")
        XCTAssertTrue(sheet.contains("let delivered = WatchBridge.shared.sendEnrollment(enrollment.oneTimeCode)"))
        XCTAssertTrue(sheet.contains("watchLinkSent = delivered"))
        XCTAssertFalse(sheet.contains("watchLinkSent = true"))
    }

    func testTheCodeIsShownSoManualEntryIsPossible() throws {
        // The Watch offers "Enter code manually" and the phone never displayed a
        // code, so that escape hatch could not be used by anyone.
        let sheet = try read("UI/Settings/AccountSheet.swift")
        XCTAssertTrue(sheet.contains("Text(watchEnrollment.oneTimeCode)"))
        XCTAssertTrue(sheet.contains("Enter code manually"))
    }

    func testAFailedLinkNamesItsOwnCause() throws {
        let bridge = try read("Sources/Voice/WatchBridge.swift")
        for cause in ["No Apple Watch is paired", "not installed on your Apple Watch", "Still connecting"] {
            XCTAssertTrue(bridge.contains(cause), "missing diagnostic: \(cause)")
        }
        let sheet = try read("UI/Settings/AccountSheet.swift")
        XCTAssertTrue(sheet.contains("WatchBridge.shared.linkDiagnostics()"))
    }

    func testTheStubKeepsTheSameSurface() throws {
        let bridge = try read("Sources/Voice/WatchBridge.swift")
        XCTAssertTrue(bridge.contains("public func linkDiagnostics() -> String { \"Apple Watch connectivity is unavailable on this device.\" }"))
    }
}
