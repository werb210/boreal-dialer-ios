import XCTest
@testable import BorealDialerWatch

// DIALER_v850_KS_CRM - a Keystone call in the Watch's recents decodes (an unknown line used to fail the whole list)
// and is labelled "Keystone". BF stays the Watch's only selectable line.
final class KeystoneLineV850Tests: XCTestCase {
    func testKeystoneRecentCallDecodes() throws {
        let call = WatchRecentCall(id: "c1", name: "Pat", number: "+14035550100", direction: .incoming,
                                   occurredAt: Date(timeIntervalSince1970: 0), line: .KS)
        let decoded = try JSONDecoder().decode(WatchRecentCall.self, from: JSONEncoder().encode(call))
        XCTAssertEqual(decoded.line, .KS)
        XCTAssertEqual(try JSONDecoder().decode(BorealLine.self, from: Data(#""KS""#.utf8)), .KS)
    }

    func testLineLabels() {
        XCTAssertEqual(BorealLine.KS.displayName, "Keystone")
        XCTAssertEqual(BorealLine.BF.displayName, "Boreal Financial")
        XCTAssertEqual(BorealLine.enabled, [.BF])
    }
}
