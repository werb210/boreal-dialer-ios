// BOREAL_DIALER_POST_CALL_DISPOSITION_v201
import XCTest
@testable import BorealDialer

final class CallDispositionTests: XCTestCase {
    /// The server rejects anything outside CALL_DISPOSITIONS with
    /// unknown_disposition, so the raw values are a contract, not a label.
    func testRawValuesMatchServerContract() {
        let expected: Set<String> = [
            "connected", "left_voicemail", "no_answer", "follow_up",
            "not_interested", "do_not_contact", "demo_booked",
            "documents_promised", "needs_lender_review",
        ]
        XCTAssertEqual(Set(CallDisposition.allCases.map(\.rawValue)), expected)
    }

    func testOrderedListsEveryCaseExactlyOnce() {
        XCTAssertEqual(CallDisposition.ordered.count, CallDisposition.allCases.count)
        XCTAssertEqual(Set(CallDisposition.ordered), Set(CallDisposition.allCases))
    }

    func testConnectedIsFirstBecauseItIsTheCommonCase() {
        XCTAssertEqual(CallDisposition.ordered.first, .connected)
    }

    /// Only the four outcomes the server actually creates a task for should
    /// promise one. Telling staff a task will appear when it will not is worse
    /// than saying nothing.
    func testOnlyServerBackedOutcomesPromiseAFollowUp() {
        let promising = CallDisposition.allCases.filter { $0.followUpNote != nil }
        XCTAssertEqual(Set(promising), Set([.followUp, .documentsPromised, .needsLenderReview, .demoBooked]))
    }

    func testEveryCaseHasAHumanLabel() {
        for option in CallDisposition.allCases {
            XCTAssertFalse(option.label.isEmpty)
            XCTAssertNotEqual(option.label, option.rawValue)
        }
    }

    func testBlankCallReferenceIsRejectedBeforeAnyRequest() async {
        do {
            _ = try await CallDispositionService.record(callRef: "   ", disposition: .connected)
            XCTFail("expected a missing reference error")
        } catch let error as DispositionError {
            guard case .missingCallReference = error else {
                return XCTFail("wrong error: \(error)")
            }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}
