// BOREAL_DIALER_POST_CALL_DISPOSITION_v201
import XCTest
import UserNotifications
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

// BOREAL_DIALER_PRESENT_DISPOSITION_v224
extension CallDispositionTests {
    func testFinishedCallIsIdentifiedByItsSid() {
        let a = FinishedCall(callSid: "CA123", endedAt: Date())
        XCTAssertEqual(a.id, "CA123")
    }

    func testTwoEndsOfTheSameCallAreEqual() {
        let at = Date()
        XCTAssertEqual(
            FinishedCall(callSid: "CA123", endedAt: at),
            FinishedCall(callSid: "CA123", endedAt: at)
        )
    }

    /// The engine publishes the sid because that is what it has; the server
    /// accepts either form, so no lookup is needed before recording an outcome.
    func testTheSidIsAnAcceptableCallReference() async {
        do {
            _ = try await CallDispositionService.record(callRef: "CA123", disposition: .connected)
        } catch let error as DispositionError {
            // A network failure here is fine; a missingCallReference is not.
            if case .missingCallReference = error {
                XCTFail("a CallSid must be accepted as a call reference")
            }
        } catch {
            // Any other transport error is acceptable in a unit test.
        }
    }
}

// BOREAL_DIALER_MISSED_CALL_ACTIONS_v239
final class MissedCallNotificationTests: XCTestCase {
    func testCategoryOffersCallBack() {
        let category = MissedCallNotification.category()
        XCTAssertEqual(category.identifier, "MISSED_CALL")
        XCTAssertEqual(category.actions.map(\.identifier), ["CALL_BACK"])
    }

    func testContentCarriesCategoryAndDialableNumber() throws {
        let content = try XCTUnwrap(MissedCallNotification.content(handle: "+1 (587) 555-0100"))
        XCTAssertEqual(content.categoryIdentifier, "MISSED_CALL")
        XCTAssertEqual(content.userInfo["phone"] as? String, "+15875550100")
    }

    func testNoNotificationForClientIdentitiesOrUnknown() {
        XCTAssertNil(MissedCallNotification.content(handle: "client:staff-42"))
        XCTAssertNil(MissedCallNotification.content(handle: "Unknown"))
    }

    func testCallBackURLParsesThroughTheExistingDeepLinkParser() throws {
        let url = try XCTUnwrap(MissedCallNotification.callBackURL(userInfo: ["type": "missed_call", "phone": "+15875550100"]))
        XCTAssertNotNil(DialerDeepLinkParser.parse(url))
        XCTAssertNil(MissedCallNotification.callBackURL(userInfo: ["type": "client_message"]))
    }
}
