// BOREAL_DIALER_WATCH_LINK_TRUTH_v340
import XCTest

final class WatchLinkTruthTests: XCTestCase {
    private func read(_ rel: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { dir.deleteLastPathComponent() }
        return try String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8)
    }

    // BOREAL_DIALER_WATCH_LINK_TRUTH_v344
    // v340 made delivery conditional on a paired Watch with the app installed,
    // because transferUserInfo is a silent no-op otherwise. v341 kept that
    // reasoning but changed the answer: the durable application context goes out
    // ALWAYS - it is held by the system and delivered whenever the Watch next
    // becomes available, including after the Watch app is first installed, which
    // is the window transferUserInfo could never cover. The one-shot transfer is
    // now the optional fast path, not the only path. This test follows the code.
    func testTheDurableContextAlwaysGoesOutAndTheTransferIsTheFastPath() throws {
        let bridge = try read("Sources/Voice/WatchBridge.swift")
        XCTAssertTrue(bridge.contains("try? session.updateApplicationContext(context)"))
        XCTAssertTrue(bridge.contains("if session.isPaired, session.isWatchAppInstalled { session.transferUserInfo(payload) }"))
    }

    func testTheContextIsStampedSoAnIdenticalCodeIsNotDropped() throws {
        // updateApplicationContext discards a dictionary equal to the last one,
        // so re-sending the same code without a stamp would silently do nothing.
        let bridge = try read("Sources/Voice/WatchBridge.swift")
        XCTAssertTrue(bridge.contains("context[\"boreal.watch.enroll.at\"] = Date().timeIntervalSince1970"))
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

    // BOREAL_DIALER_WATCH_LINK_TRUTH_v344
    // "not installed on your Apple Watch" was a v340 diagnostic and v341 removed
    // it deliberately: with a durable context, an uninstalled Watch app is no
    // longer a failure to report, it is a state that resolves itself the moment
    // the app appears. The two causes that still block a link are an unpaired
    // Watch and a session that has not finished activating.
    func testAFailedLinkNamesItsOwnCause() throws {
        let bridge = try read("Sources/Voice/WatchBridge.swift")
        for cause in ["No Apple Watch is paired", "Still connecting"] {
            XCTAssertTrue(bridge.contains(cause), "missing diagnostic: \(cause)")
        }
        XCTAssertTrue(bridge.contains("Ready. Open Boreal on your Watch and it will link itself."))
        let sheet = try read("UI/Settings/AccountSheet.swift")
        XCTAssertTrue(sheet.contains("WatchBridge.shared.linkDiagnostics()"))
    }

    // BOREAL_DIALER_WATCH_LINK_TRUTH_v344 - the half v341 added: the Watch asks.
    func testTheWatchCanAskRatherThanOnlyBeingPushedTo() throws {
        let store = try read("Watch/WatchEventStore.swift")
        XCTAssertTrue(store.contains("session.sendMessage([WatchPayload.enrollRequestKey: true])"))
        XCTAssertTrue(store.contains("didReceiveApplicationContext"))
        let bridge = try read("Sources/Voice/WatchBridge.swift")
        XCTAssertTrue(bridge.contains("message[WatchPayload.enrollRequestKey] != nil"))
    }

    func testTheStubKeepsTheSameSurface() throws {
        let bridge = try read("Sources/Voice/WatchBridge.swift")
        XCTAssertTrue(bridge.contains("public func linkDiagnostics() -> String { \"Apple Watch connectivity is unavailable on this device.\" }"))
    }
}
