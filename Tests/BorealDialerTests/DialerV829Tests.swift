import XCTest
@testable import BorealDialer

// BOREAL_DIALER_v829_RELIABILITY - readable errors, the outgoing call's callee state, connect-failure reasons and the
// event log that reports calls to BF-Server.
final class DialerV829Tests: XCTestCase {

    func testServerReasonIsKeptAndReadable() {
        let body = Data(#"{"success":false,"error":"call_not_found","message":"This call isn't linked to you, so the outcome could not be saved."}"#.utf8)
        let reason = APIError.serverReason(from: body)
        XCTAssertEqual(reason.code, "call_not_found")
        let error = APIError.http(status: 404, code: reason.code, message: reason.message)
        XCTAssertEqual(error.localizedDescription, "This call isn't linked to you yet, so the outcome wasn't saved.")
        XCTAssertFalse(error.localizedDescription.contains("APIError"))
    }

    func testNestedAndPlainErrorBodies() {
        let nested = APIError.serverReason(from: Data(#"{"error":{"code":"invalid_phone","message":"phone must be an E.164 number"}}"#.utf8))
        XCTAssertEqual(nested.code, "invalid_phone")
        XCTAssertEqual(nested.message, "phone must be an E.164 number")
        XCTAssertNil(APIError.serverReason(from: Data("not json".utf8)).code)
    }

    func testUnknownErrorsStillSaySomethingUseful() {
        XCTAssertEqual(APIError.http(status: 500, code: "disposition_failed", message: "null value in column \"x\" violates not-null constraint").localizedDescription,
                       "The server had a problem (500). Try again in a moment.")
        XCTAssertEqual(APIError.http(status: 409, code: "phone_in_use", message: nil).localizedDescription, "The server refused that (phone_in_use).")
        XCTAssertEqual(APIError.http(status: 422, code: nil, message: "Enter the amount as a number, or leave it blank.").localizedDescription,
                       "Enter the amount as a number, or leave it blank.")
        XCTAssertEqual(APIError.unauthorized.localizedDescription, "Your session has expired. Sign in again.")
        XCTAssertFalse(OfflineQueue.isOffline(APIError.http(status: 503, code: nil, message: nil)))
    }

    func testCalleeOutcomeFromParticipantStatus() {
        XCTAssertEqual(ConferenceSession.outcome(forStatus: "pending_dial"), .ringing)
        XCTAssertEqual(ConferenceSession.outcome(forStatus: "ringing"), .ringing)
        XCTAssertEqual(ConferenceSession.outcome(forStatus: nil), .ringing)
        XCTAssertEqual(ConferenceSession.outcome(forStatus: "joined"), .answered)
        XCTAssertEqual(ConferenceSession.outcome(forStatus: "busy"), .unanswered("The line is busy."))
        XCTAssertEqual(ConferenceSession.outcome(forStatus: "no-answer"), .unanswered("There was no answer."))
        XCTAssertEqual(ConferenceSession.outcome(forStatus: "failed"), .unanswered("The call could not be completed."))
        XCTAssertEqual(ConferenceSession.outcome(forStatus: "left"), .unanswered("The call could not be completed."))
        XCTAssertEqual(ConferenceSession.outcome(forStatus: "in-progress"), .answered)
    }

    func testParticipantStatusDecodes() throws {
        let json = Data(#"{"participants":[{"id":"p1","display_name":"Jane","phone_number":"+15875550100","muted":false,"on_hold":false,"status":"busy","kind":"pstn"}]}"#.utf8)
        struct Detail: Decodable { let participants: [ConferenceSession.ConferenceParticipant] }
        let decoded = try JSONDecoder().decode(Detail.self, from: json)
        XCTAssertEqual(decoded.participants.first?.status, "busy")
    }

    @MainActor
    func testConnectFailureReasons() {
        XCTAssertEqual(VoiceEngine.connectFailureMessage(code: 20104), "Your calling session expired. Close and reopen the app, then try again.")
        XCTAssertEqual(VoiceEngine.connectFailureMessage(code: 31486), "The line is busy.")
        XCTAssertEqual(VoiceEngine.connectFailureMessage(code: 31005), "The call couldn't connect: the network dropped. Check your signal and try again.")
        XCTAssertEqual(VoiceEngine.connectFailureMessage(code: 99999), "The call couldn't connect (error 99999). Try again.")
    }

    func testEventLogKeepsReleaseEvents() {
        let before = DialerEventLog.shared.pendingCount
        Telemetry.event("v829_test_event", metadata: ["a": "1"], callRef: "CA123")
        XCTAssertGreaterThanOrEqual(DialerEventLog.shared.pendingCount, min(before + 1, DialerEventLog.maxPending))
        XCTAssertTrue(DialerEventLog.urgent.contains("connect_timeout"))
    }
}
