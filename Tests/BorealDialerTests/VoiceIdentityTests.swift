import Foundation
import XCTest
@testable import BorealDialer

@MainActor
final class VoiceIdentityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        IdentityManager.shared.clear()
    }

    override func tearDown() {
        IdentityManager.shared.clear()
        super.tearDown()
    }

    func testMatchingIdentityDoesNotStartSessionTeardown() async {
        XCTAssertTrue(IdentityManager.shared.configure(identity: "alice"))
        let recorder = IdentityMismatchRecorder()

        VoiceManager.shared.configureIdentityIfNeeded(from: token(identity: "alice")) {
            recorder.recordLogoutAndInvalidation()
        }
        await Task.yield()

        XCTAssertEqual(IdentityManager.shared.identity, "alice")
        XCTAssertEqual(recorder.logoutStarts, 0)
        XCTAssertEqual(recorder.invalidationStarts, 0)
    }

    func testMismatchedIdentityStartsTeardownWithoutInstallingIdentity() async {
        XCTAssertTrue(IdentityManager.shared.configure(identity: "alice"))
        let recorder = IdentityMismatchRecorder()

        VoiceManager.shared.configureIdentityIfNeeded(from: token(identity: "mallory")) {
            recorder.recordLogoutAndInvalidation()
        }
        await Task.yield()

        XCTAssertEqual(recorder.logoutStarts, 1)
        XCTAssertEqual(recorder.invalidationStarts, 1)
        XCTAssertEqual(IdentityManager.shared.identity, "alice")
    }

    func testMissingIdentityIsConfiguredFromValidToken() async {
        let recorder = IdentityMismatchRecorder()

        VoiceManager.shared.configureIdentityIfNeeded(from: token(identity: "alice")) {
            recorder.recordLogoutAndInvalidation()
        }
        await Task.yield()

        XCTAssertEqual(IdentityManager.shared.identity, "alice")
        XCTAssertEqual(recorder.logoutStarts, 0)
        XCTAssertEqual(recorder.invalidationStarts, 0)
    }

    func testMalformedOrIdentityFreeJWTDoesNotMutateIdentity() async {
        XCTAssertTrue(IdentityManager.shared.configure(identity: "alice"))
        let recorder = IdentityMismatchRecorder()
        let malformed = ["not-a-jwt", token(payload: ["grants": [:]])]

        for token in malformed {
            VoiceManager.shared.configureIdentityIfNeeded(from: token) {
                recorder.recordLogoutAndInvalidation()
            }
        }
        await Task.yield()

        XCTAssertEqual(IdentityManager.shared.identity, "alice")
        XCTAssertEqual(recorder.logoutStarts, 0)
        XCTAssertEqual(recorder.invalidationStarts, 0)
    }

    private func token(identity: String) -> String {
        token(payload: ["grants": ["identity": identity]])
    }

    private func token(payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let body = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(body).signature"
    }
}

@MainActor
private final class IdentityMismatchRecorder {
    private(set) var logoutStarts = 0
    private(set) var invalidationStarts = 0

    func recordLogoutAndInvalidation() {
        logoutStarts += 1
        invalidationStarts += 1
    }
}
