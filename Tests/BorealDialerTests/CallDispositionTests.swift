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

// BOREAL_DIALER_FACE_ID_v244
final class AppLockPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testLocksSignedInSessionOnColdStart() {
        XCTAssertTrue(AppLockPolicy.shouldLock(authenticated: true, biometryAvailable: true, inCall: false,
                                               coldStart: true, backgroundedAt: nil, now: now))
    }

    func testLocksAfterAMinuteButNotAQuickSwitch() {
        XCTAssertTrue(AppLockPolicy.shouldLock(authenticated: true, biometryAvailable: true, inCall: false,
                                               coldStart: false, backgroundedAt: now.addingTimeInterval(-60), now: now))
        XCTAssertFalse(AppLockPolicy.shouldLock(authenticated: true, biometryAvailable: true, inCall: false,
                                                coldStart: false, backgroundedAt: now.addingTimeInterval(-5), now: now))
    }

    func testNeverLocksDuringACallSignedOutOrWithoutBiometry() {
        XCTAssertFalse(AppLockPolicy.shouldLock(authenticated: true, biometryAvailable: true, inCall: true,
                                                coldStart: true, backgroundedAt: nil, now: now))
        XCTAssertFalse(AppLockPolicy.shouldLock(authenticated: false, biometryAvailable: true, inCall: false,
                                                coldStart: true, backgroundedAt: nil, now: now))
        XCTAssertFalse(AppLockPolicy.shouldLock(authenticated: true, biometryAvailable: false, inCall: false,
                                                coldStart: true, backgroundedAt: nil, now: now))
    }
}

// BOREAL_DIALER_CALL_SUMMARY_v246
final class CallSummaryServiceTests: XCTestCase {
    func testDecodesTheServerEnvelope() throws {
        let json = Data(#"{"status":"ok","data":{"status":"ready","summary":"- Walter sends statements Friday","contactId":"c1"}}"#.utf8)
        XCTAssertEqual(try CallSummaryService.decode(json), CallSummaryResult(status: "ready", summary: "- Walter sends statements Friday"))
    }

    func testKeepsPollingOnlyWhilePendingAndWithinTheLimit() {
        XCTAssertTrue(CallSummaryService.shouldKeepPolling(nil, attempt: 0))
        XCTAssertTrue(CallSummaryService.shouldKeepPolling(CallSummaryResult(status: "pending", summary: nil), attempt: 3))
        XCTAssertFalse(CallSummaryService.shouldKeepPolling(CallSummaryResult(status: "ready", summary: "S"), attempt: 3))
        XCTAssertFalse(CallSummaryService.shouldKeepPolling(CallSummaryResult(status: "none", summary: nil), attempt: 3))
        XCTAssertFalse(CallSummaryService.shouldKeepPolling(nil, attempt: CallSummaryService.maxAttempts))
    }
}

// BOREAL_DIALER_APP_INTENTS_v247
final class BorealIntentTextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNoMeetingOrPastMeeting() {
        XCTAssertEqual(BorealIntentText.nextMeeting(nil, now: now), "You have no upcoming meetings in Boreal.")
        XCTAssertEqual(BorealIntentText.nextMeeting((title: "ABC", startsAt: now.addingTimeInterval(-60)), now: now),
                       "You have no upcoming meetings in Boreal.")
    }

    func testUpcomingMeetingNamesTheMeeting() {
        let text = BorealIntentText.nextMeeting((title: "ABC Manufacturing", startsAt: now.addingTimeInterval(3600)), now: now)
        XCTAssertTrue(text.hasPrefix("Your next meeting is ABC Manufacturing at "))
    }

    func testDueCountsReadNaturally() {
        XCTAssertEqual(BorealIntentText.due(missedCalls: 0, tasksDue: 0), "Nothing is due in Boreal right now.")
        XCTAssertEqual(BorealIntentText.due(missedCalls: 1, tasksDue: 0), "You have 1 missed call.")
        XCTAssertEqual(BorealIntentText.due(missedCalls: 2, tasksDue: 3), "You have 2 missed calls and 3 tasks due.")
    }
}

// BOREAL_DIALER_START_CALL_ACTIVITY_v248
final class StartCallActivityTests: XCTestCase {
    func testBuildsADialLinkTheExistingParserAccepts() throws {
        let url = try XCTUnwrap(StartCallActivity.dialURL(handle: "+1 (587) 555-0100"))
        XCTAssertEqual(DialerDeepLinkParser.parse(url), .phone("+15875550100", start: true))
    }

    func testNationalNumbersFromContactCardsBecomeE164() throws {
        let url = try XCTUnwrap(StartCallActivity.dialURL(handle: "(587) 555-0100"))
        XCTAssertEqual(DialerDeepLinkParser.parse(url), .phone("+15875550100", start: true))
        XCTAssertNil(StartCallActivity.dialURL(handle: "44 20 7946 0958"))
    }

    func testIgnoresHandlesThatAreNotPhoneNumbers() {
        XCTAssertNil(StartCallActivity.dialURL(handle: nil))
        XCTAssertNil(StartCallActivity.dialURL(handle: "  "))
        XCTAssertNil(StartCallActivity.dialURL(handle: "client:staff-42"))
    }
}

// BOREAL_DIALER_SUGGESTED_TASKS_v254
final class SuggestedTaskTests: XCTestCase {
    func testDecodesSuggestionsFromTheSummaryEnvelope() throws {
        let json = Data(#"{"status":"ok","data":{"status":"ready","summary":"S","contactId":"c1","suggestedTasks":[{"title":"Call Walter","type":"CALL","dueInDays":3}]}}"#.utf8)
        let result = try CallSummaryService.decode(json)
        XCTAssertEqual(result.contactId, "c1")
        XCTAssertEqual(result.suggestedTasks, [SuggestedCallTask(title: "Call Walter", type: "CALL", dueInDays: 3)])
    }

    func testOlderServerWithoutSuggestionsStillDecodes() throws {
        let json = Data(#"{"status":"ok","data":{"status":"ready","summary":"S"}}"#.utf8)
        XCTAssertNil(try CallSummaryService.decode(json).suggestedTasks)
    }

    func testTaskBodyKeepsTheTypeWithAContactAndFallsBackToTodoWithout() {
        let task = SuggestedCallTask(title: "Call Walter", type: "CALL", dueInDays: 2)
        let withContact = SuggestedTaskService.body(for: task, contactId: "c1")
        XCTAssertEqual(withContact["type"] as? String, "CALL")
        XCTAssertEqual(withContact["contact_id"] as? String, "c1")
        XCTAssertEqual(withContact["priority"] as? String, "MEDIUM")
        let without = SuggestedTaskService.body(for: task, contactId: nil)
        XCTAssertEqual(without["type"] as? String, "TODO")
        XCTAssertNil(without["contact_id"])
    }

    func testDetailReadsNaturally() {
        XCTAssertEqual(SuggestedCallTask(title: "x", type: "EMAIL", dueInDays: 1).detail, "Email - tomorrow")
        XCTAssertEqual(SuggestedCallTask(title: "x", type: "TODO", dueInDays: 5).detail, "To-do - in 5 days")
    }
}
