import XCTest
@testable import BorealDialer

// BOREAL_DIALER_v831_DIALER_POLISH - offline queue safety, staying signed in, staff-only sign-in, the outcome sheet's
// name and length, call logs that say which way the call went, full caller ID, the call-waiting notice.
final class DialerV831Tests: XCTestCase {

    private func token(_ claims: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: claims)
        let payload = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJIUzI1NiJ9.\(payload).sig"
    }

    override func setUp() {
        super.setUp()
        OfflineQueue.shared.clear()
    }

    override func tearDown() {
        OfflineQueue.shared.clear()
        super.tearDown()
    }

    // MARK: Session

    func testReadsTheSignInClaims() {
        let exp = Date().addingTimeInterval(3600).timeIntervalSince1970.rounded()
        let t = token(["sub": "user-1", "role": "Staff", "exp": exp])
        XCTAssertEqual(JWTClaims.subject(of: t), "user-1")
        XCTAssertEqual(JWTClaims.role(of: t), "Staff")
        XCTAssertEqual(JWTClaims.expiry(of: t)?.timeIntervalSince1970, exp)
        XCTAssertNil(JWTClaims.subject(of: "not-a-token"))
        XCTAssertNil(JWTClaims.subject(of: nil))
    }

    func testRenewsOnlyInTheLastTwoDays() {
        let now = Date()
        XCTAssertTrue(SessionRenewal.shouldRenew(expiry: now.addingTimeInterval(36 * 3600), now: now))
        XCTAssertFalse(SessionRenewal.shouldRenew(expiry: now.addingTimeInterval(5 * 24 * 3600), now: now))
        XCTAssertFalse(SessionRenewal.shouldRenew(expiry: now.addingTimeInterval(-60), now: now)) // already over
        XCTAssertFalse(SessionRenewal.shouldRenew(expiry: nil, now: now))
    }

    func testOnlyStaffRolesSignIn() {
        XCTAssertTrue(AuthService.isCallingRole("Staff"))
        XCTAssertTrue(AuthService.isCallingRole("admin"))
        XCTAssertTrue(AuthService.isCallingRole("Marketing"))
        XCTAssertFalse(AuthService.isCallingRole("client"))
        XCTAssertFalse(AuthService.isCallingRole("Referrer"))
        XCTAssertFalse(AuthService.isCallingRole(nil))
    }

    func testANumberThatIsNotStaffIsToldSo() {
        let message = LoginView.codeErrorMessage(APIError.http(status: 403, code: "not_staff", message: nil))
        XCTAssertTrue(message.contains("isn't set up as a Boreal staff account"))
        XCTAssertEqual(LoginView.codeErrorMessage(APIError.http(status: 401, code: nil, message: nil)), "That code didn't work. Please try again.")
    }

    // MARK: Offline queue

    func testASavedChangeKnowsWhoSavedItAndKeepsItsKey() {
        let suite = "DialerV831Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = token(["sub": "user-1", "role": "Staff"])
        let queue = OfflineQueue(defaults: defaults, tokenProvider: { session })
        let key = UUID()
        queue.enqueue(label: "Call outcome", path: "/telephony/calls/CA1/disposition", body: Data("{}".utf8), id: key)
        queue.enqueue(label: "Call outcome", path: "/telephony/calls/CA1/disposition", body: Data("{}".utf8), id: key)
        let items = queue.load()
        XCTAssertEqual(items.count, 1) // the same change is never queued twice
        XCTAssertEqual(items.first?.id, key)
        XCTAssertEqual(items.first?.ownerId, "user-1")
    }

    func testRefusalsAreKeptWithAReasonAndOutagesAreRetried() {
        XCTAssertEqual(OfflineQueue.classify(URLError(.notConnectedToInternet)), .stop)
        XCTAssertEqual(OfflineQueue.classify(APIError.unauthorized), .stop)
        XCTAssertEqual(OfflineQueue.classify(APIError.http(status: 503, code: nil, message: nil)), .retry)
        XCTAssertEqual(OfflineQueue.classify(APIError.http(status: 409, code: "request_in_progress", message: nil)), .retry)
        XCTAssertEqual(OfflineQueue.classify(APIError.http(status: 404, code: "call_not_found", message: nil)),
                       .refused(APIError.knownCodes["call_not_found"]!))
    }

    func testARefusedChangeCanBeDiscarded() {
        OfflineQueue.shared.enqueue(label: "Task", path: "/tasks", body: Data("{}".utf8))
        let id = OfflineQueue.shared.load()[0].id
        OfflineQueue.shared.discard(id)
        XCTAssertTrue(OfflineQueue.shared.load().isEmpty)
    }

    func testQueuedItemsFromBeforeThisVersionStillDecode() throws {
        let legacy = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","label":"Task","path":"/tasks","method":"POST","silo":"BF","createdAt":0,"attempts":3}]"#
        let decoded = try JSONDecoder().decode([QueuedRequest].self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.first?.ownerId)
        XCTAssertNil(decoded.first?.failure)
    }

    func testTheBarSaysWhatWasNotSaved() {
        XCTAssertNil(OfflineStatusBar.failedText(0))
        XCTAssertEqual(OfflineStatusBar.failedText(1), "1 saved change couldn't be sent. Tap to review.")
        XCTAssertEqual(OfflineStatusBar.failedText(3), "3 saved changes couldn't be sent. Tap to review.")
    }

    // MARK: Calls

    func testOutcomeSheetSaysHowLongTheCallWas() {
        XCTAssertNil(FinishedCall.durationText(0))
        XCTAssertEqual(FinishedCall.durationText(42), "42s")
        XCTAssertEqual(FinishedCall.durationText(252), "4m 12s")
        XCTAssertEqual(FinishedCall.durationText(3_900), "1h 05m")
        XCTAssertEqual(FinishedCall(callSid: "CA1", endedAt: Date(), contactName: "Jane Doe", durationSeconds: 61).durationText, "1m 01s")
    }

    func testCallLogsSayWhichWayTheCallWent() throws {
        let inbound = try XCTUnwrap(API.callLogBody(duration: 42, status: "ended", number: "+15875550142", callSid: "CA1", direction: "inbound"))
        let i = try XCTUnwrap(JSONSerialization.jsonObject(with: inbound) as? [String: Any])
        XCTAssertEqual(i["direction"] as? String, "inbound")
        XCTAssertEqual(i["from_number"] as? String, "+15875550142")
        XCTAssertNil(i["to_number"])
        let outbound = try XCTUnwrap(API.callLogBody(duration: 0, status: "failed", number: "+15875550142", callSid: nil, direction: "outbound"))
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: outbound) as? [String: Any])
        XCTAssertEqual(o["to_number"] as? String, "+15875550142")
        XCTAssertEqual(o["event_type"] as? String, "call.failed")
        XCTAssertNil(API.callLogBody(duration: 0, status: "ended", number: nil, callSid: nil, direction: "outbound"))
    }

    @MainActor
    func testASecondCallsOutcomeWaitsItsTurn() async {
        let engine = VoiceEngine.shared
        engine.finishedCall = nil
        engine.publishFinishedCall(callSid: "CA-first")
        engine.publishFinishedCall(callSid: "CA-second")
        engine.publishFinishedCall(callSid: "CA-second")
        XCTAssertEqual(engine.finishedCall?.callSid, "CA-first")
        XCTAssertEqual(engine.waitingOutcomes.map(\.callSid), ["CA-second"])
        engine.publishFinishedCall(callSid: nil) // a call with no sid changes nothing
        XCTAssertEqual(engine.finishedCall?.callSid, "CA-first")

        engine.outcomeSheetClosed()
        XCTAssertNil(engine.finishedCall)
        try? await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertEqual(engine.finishedCall?.callSid, "CA-second")
        XCTAssertTrue(engine.waitingOutcomes.isEmpty)
        engine.finishedCall = nil
    }

    @MainActor
    func testThePauseAfterACallIsNotACall() {
        XCTAssertFalse(VoiceEngine.shared.isOnCall)
    }

    func testCallWaitingNoticeNamesTheCaller() throws {
        let content = try XCTUnwrap(MissedCallNotification.content(handle: "+14035550100", name: "Jane Doe", whileOnCall: true))
        XCTAssertEqual(content.title, "Missed while you were on a call")
        XCTAssertEqual(content.body, "Jane Doe · (403) 555-0100")
        XCTAssertEqual(content.userInfo["phone"] as? String, "+14035550100")
        XCTAssertEqual(MissedCallNotification.content(handle: "+14035550100")?.title, "Missed call")
    }

    func testSummaryFromTheCallRoute() throws {
        let json = Data(#"{"status":"ready","summary":"Talked rates.","contactId":"c1","suggestedTasks":[{"title":"Send term sheet","type":"EMAIL","dueInDays":2}]}"#.utf8)
        let result = try CallSummaryService.decode(json)
        XCTAssertEqual(result.status, "ready")
        XCTAssertEqual(result.suggestedTasks, [SuggestedCallTask(title: "Send term sheet", type: "EMAIL", dueInDays: 2)])
    }

    // MARK: Caller ID

    @MainActor
    func testCallerIDTakesEveryContactOncePerNumber() {
        let labels = CallDirectoryManager.labels(from: [
            .init(number: "+14035550142", label: "Jane Doe"),
            .init(number: "+14035550142", label: "Old Jane"),
            .init(number: "+15875550100", label: "  "),
            .init(number: "4035550199", label: "Not E.164"),
        ])
        XCTAssertEqual(labels, [14035550142: "Jane Doe"])
    }

    @MainActor
    func testCallerIDRefreshesEverySixHours() {
        let now = Date()
        XCTAssertTrue(CallDirectoryManager.isDue(lastRefresh: nil, now: now))
        XCTAssertFalse(CallDirectoryManager.isDue(lastRefresh: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(CallDirectoryManager.isDue(lastRefresh: now.addingTimeInterval(-7 * 3600), now: now))
    }
}
