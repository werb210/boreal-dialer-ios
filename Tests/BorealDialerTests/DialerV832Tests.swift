import XCTest
@testable import BorealDialer

// BOREAL_DIALER_v832_SIGNOUT_ALERTS - a phone nobody is signed in to stops ringing, and a missed call shows once.
final class DialerV832Tests: XCTestCase {

    override func tearDown() {
        PendingSignOut.clear()
        super.tearDown()
    }

    func testCallsToASignedOutPhoneAreTurnedAway() {
        XCTAssertEqual(CallKitReporter.decide(isDuplicate: false, isBusy: false, isSignedOut: true), .rejectSignedOut)
        XCTAssertEqual(CallKitReporter.decide(isDuplicate: false, isBusy: true, isSignedOut: true), .rejectSignedOut)
        // A second delivery of the call already ringing is still never rejected.
        XCTAssertEqual(CallKitReporter.decide(isDuplicate: true, isBusy: false, isSignedOut: true), .rejectDuplicate)
        XCTAssertEqual(CallKitReporter.decide(isDuplicate: false, isBusy: false), .ring)
    }

    func testAnUnfinishedSignOutIsKeptUntilItIsSent() throws {
        PendingSignOut.clear()
        PendingSignOut.rememberAlertUnregister(pushToken: "abc123", staffToken: "jwt")
        PendingSignOut.rememberTwilioUnregister(accessToken: "twilio", deviceToken: Data([1, 2, 3]))
        let work = try XCTUnwrap(PendingSignOut.load())
        XCTAssertEqual(work.alertPushToken, "abc123")
        XCTAssertEqual(work.staffToken, "jwt")
        XCTAssertEqual(work.twilioAccessToken, "twilio")
        XCTAssertEqual(work.voipDeviceToken, Data([1, 2, 3]))
        XCTAssertFalse(work.isEmpty)
        XCTAssertFalse(PendingSignOut.isStale(work))
        XCTAssertTrue(PendingSignOut.isStale(work, now: Date().addingTimeInterval(8 * 24 * 3600)))
        PendingSignOut.clear()
        XCTAssertNil(PendingSignOut.load())
    }

    func testOnlyAMissingSignInCountsAsSignedOut() {
        XCTAssertTrue(PendingSignOut.isDefinitelySignedOut(.notFound))
        XCTAssertTrue(PendingSignOut.isDefinitelySignedOut(.found(Data())))
        XCTAssertFalse(PendingSignOut.isDefinitelySignedOut(.found(Data("jwt".utf8))))
        XCTAssertFalse(PendingSignOut.isDefinitelySignedOut(.locked))
        XCTAssertFalse(PendingSignOut.isDefinitelySignedOut(.failed(-34018)))
        XCTAssertTrue(PendingSignOut.twilioTokenExpired(code: 20104))
        XCTAssertFalse(PendingSignOut.twilioTokenExpired(code: 31005))
    }

    func testAlertUnregisterIsDoneWhenTheServerNoLongerSends() {
        XCTAssertTrue(PendingSignOut.alertUnregisterIsDone(status: 204))
        XCTAssertTrue(PendingSignOut.alertUnregisterIsDone(status: 401))
        XCTAssertTrue(PendingSignOut.alertUnregisterIsDone(status: 404))
        XCTAssertFalse(PendingSignOut.alertUnregisterIsDone(status: 0))
        XCTAssertFalse(PendingSignOut.alertUnregisterIsDone(status: 503))
    }

    func testTheServersMissedCallReplacesThePhonesOwn() {
        let now = Date()
        let delivered = [
            MissedCallDedupe.Delivered(id: "local-1", userInfo: ["type": "missed_call", "phone": "+14035550100", MissedCallDedupe.localKey: true], date: now.addingTimeInterval(-60)),
            MissedCallDedupe.Delivered(id: "local-other", userInfo: ["type": "missed_call", "phone": "+15875550199", MissedCallDedupe.localKey: true], date: now),
            MissedCallDedupe.Delivered(id: "local-old", userInfo: ["type": "missed_call", "phone": "+14035550100", MissedCallDedupe.localKey: true], date: now.addingTimeInterval(-3600)),
            MissedCallDedupe.Delivered(id: "voicemail", userInfo: ["type": "voicemail", "phone": "+14035550100"], date: now),
        ]
        XCTAssertEqual(MissedCallDedupe.localAlertIds(for: "4035550100", in: delivered, now: now), ["local-1"])
        XCTAssertFalse(MissedCallDedupe.serverAlerted(for: "+14035550100", in: delivered, now: now))
    }

    func testThePhoneSkipsItsOwnWhenTheServersIsShowing() {
        let now = Date()
        let delivered = [MissedCallDedupe.Delivered(id: "server", userInfo: ["type": "missed_call", "phone": "+14035550100"], date: now)]
        XCTAssertTrue(MissedCallDedupe.serverAlerted(for: "(403) 555-0100", in: delivered, now: now))
        XCTAssertFalse(MissedCallDedupe.serverAlerted(for: "+15875550199", in: delivered, now: now))
    }

    func testThePhonesOwnAlertIsMarked() throws {
        let content = try XCTUnwrap(MissedCallNotification.content(handle: "+14035550100"))
        XCTAssertTrue(MissedCallDedupe.isLocal(content.userInfo))
        XCTAssertTrue(MissedCallDedupe.isMissedCall(content.userInfo))
    }
}
