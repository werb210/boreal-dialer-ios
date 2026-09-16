import XCTest
@testable import BorealDialer

// BOREAL_DIALER_FACE_ID_SIGN_IN_v299
final class FaceIDSignInV299Tests: XCTestCase {
    override func setUp() {
        super.setUp()
        FaceIDSignIn.shared.clear()
        UserDefaults.standard.removeObject(forKey: "boreal.faceid.offered")
    }

    func testNotEnrolledByDefault() {
        XCTAssertFalse(FaceIDSignIn.shared.isEnrolled)
        XCTAssertNil(FaceIDSignIn.shared.credentialId)
    }

    func testSignInWithoutEnrollmentFails() async {
        do {
            _ = try await FaceIDSignIn.shared.signIn()
            XCTFail("expected notEnrolled")
        } catch FaceIDSignInError.notEnrolled {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testOfferIsRememberedSoItIsOnlyAskedOnce() {
        XCTAssertFalse(FaceIDSignIn.shared.hasBeenOffered)
        FaceIDSignIn.shared.markOffered()
        XCTAssertTrue(FaceIDSignIn.shared.hasBeenOffered)
    }
}
