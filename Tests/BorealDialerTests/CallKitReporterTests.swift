// BOREAL_DIALER_CALLKIT_REPORTER_v789
// Every VoIP push must report a call to CallKit, and the PushKit completion
// must run only after CallKit's reportNewIncomingCall callback. These drive
// CallKitReporter with a fake provider and a fake Twilio invite.
import CallKit
import XCTest
@testable import BorealDialer

final class FakeCallKitProvider: CallKitProviding {
    struct Reported {
        let uuid: UUID
        let handle: String?
        let completion: (Error?) -> Void
    }

    var reported: [Reported] = []
    var ended: [(uuid: UUID, reason: CXCallEndedReason)] = []
    var updated: [UUID] = []

    func reportIncoming(uuid: UUID, update: CXCallUpdate, completion: @escaping (Error?) -> Void) {
        reported.append(Reported(uuid: uuid, handle: update.remoteHandle?.value, completion: completion))
    }

    func reportEnded(uuid: UUID, at date: Date, reason: CXCallEndedReason) {
        ended.append((uuid, reason))
    }

    func reportUpdated(uuid: UUID, update: CXCallUpdate) {
        updated.append(uuid)
    }

    /// CallKit answers the most recent report.
    func answerLast(error: Error? = nil) {
        reported.last?.completion(error)
    }
}

final class FakeInvite: IncomingCallInvite {
    let callSid: String
    let uuid = UUID()
    let from: String?
    private(set) var rejected = 0

    init(callSid: String = "CA-1", from: String? = "+14165550123") {
        self.callSid = callSid
        self.from = from
    }

    func reject() { rejected += 1 }
}

private let twilioPayload: [AnyHashable: Any] = [
    "twi_message_type": "twilio.voice.call",
    "twi_call_sid": "CA-1"
]

final class CallKitReporterTests: XCTestCase {

    @MainActor
    private func makeReporter(busy: Bool = false,
                              twilio: @escaping @MainActor ([AnyHashable: Any]) -> Bool = { _ in false })
        -> (CallKitReporter, FakeCallKitProvider) {
        let provider = FakeCallKitProvider()
        let reporter = CallKitReporter(provider: provider, isLineBusy: { busy }, handleTwilioPayload: twilio)
        reporter.ensureProvider = {}
        return (reporter, provider)
    }

    @MainActor
    private func ringingUpdate() -> CXCallUpdate {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: "+14165550123")
        return update
    }

    func testDecisionTable() {
        XCTAssertEqual(CallKitReporter.decide(isDuplicate: false, isBusy: false), .ring)
        XCTAssertEqual(CallKitReporter.decide(isDuplicate: true, isBusy: false), .rejectDuplicate)
        XCTAssertEqual(CallKitReporter.decide(isDuplicate: true, isBusy: true), .rejectDuplicate)
        XCTAssertEqual(CallKitReporter.decide(isDuplicate: false, isBusy: true), .rejectBusy)
    }

    @MainActor
    func testUnrecognisedPayloadReportsThenEndsAsFailedBeforeCompleting() {
        var twilioCalled = false
        let (reporter, provider) = makeReporter(twilio: { _ in twilioCalled = true; return true })
        var completions = 0

        reporter.handleVoIPPush(["type": "client_message"]) { completions += 1 }

        XCTAssertFalse(twilioCalled, "an unrecognised payload is never handed to Twilio")
        XCTAssertEqual(provider.reported.count, 1, "iOS requires a reported call for every VoIP push")
        XCTAssertEqual(completions, 0, "completion waits for CallKit's callback")
        XCTAssertTrue(provider.ended.isEmpty)

        provider.answerLast()

        XCTAssertEqual(completions, 1)
        XCTAssertEqual(provider.ended.count, 1)
        XCTAssertEqual(provider.ended.first?.uuid, provider.reported.first?.uuid)
        XCTAssertEqual(provider.ended.first?.reason, .failed)
    }

    @MainActor
    func testPayloadTwilioRefusesStillReportsAFailedCall() {
        let (reporter, provider) = makeReporter(twilio: { _ in false })
        var completions = 0

        reporter.handleVoIPPush(twilioPayload) { completions += 1 }
        XCTAssertEqual(provider.reported.count, 1)
        provider.answerLast()

        XCTAssertEqual(provider.ended.first?.reason, .failed)
        XCTAssertEqual(completions, 1)
    }

    @MainActor
    func testTwilioAcceptingWithoutAnInviteStillReportsAFailedCall() {
        let (reporter, provider) = makeReporter(twilio: { _ in true })
        var completions = 0

        reporter.handleVoIPPush(twilioPayload) { completions += 1 }
        provider.answerLast()

        XCTAssertEqual(provider.reported.count, 1)
        XCTAssertEqual(provider.ended.first?.reason, .failed)
        XCTAssertEqual(completions, 1)
    }

    @MainActor
    func testNewInviteRingsSynchronouslyAndCompletesAfterCallKit() {
        let invite = FakeInvite()
        var reporter: CallKitReporter?
        var accepted: Bool?
        let (made, provider) = makeReporter(twilio: { _ in
            // Twilio calls its NotificationDelegate synchronously, inside the push.
            reporter?.receive(invite: invite, firstDelivery: true) { ringing in
                reporter?.reportRinging(uuid: ringing.uuid, handle: ringing.from ?? "", update: self.ringingUpdate()) { accepted = $0 }
            }
            return true
        })
        reporter = made
        var completions = 0

        made.handleVoIPPush(twilioPayload) { completions += 1 }

        XCTAssertEqual(provider.reported.count, 1, "reported before handleVoIPPush returned")
        XCTAssertEqual(provider.reported.first?.uuid, invite.uuid)
        XCTAssertEqual(completions, 0)

        provider.answerLast()

        XCTAssertEqual(accepted, true)
        XCTAssertEqual(completions, 1)
        XCTAssertTrue(provider.ended.isEmpty, "a ringing call is not ended")
        XCTAssertEqual(invite.rejected, 0)
    }

    @MainActor
    func testDuplicateInviteIsReportedAndEndedUnansweredButNotRejected() {
        let invite = FakeInvite()
        var reporter: CallKitReporter?
        var rang = false
        let (made, provider) = makeReporter(twilio: { _ in
            reporter?.receive(invite: invite, firstDelivery: false) { _ in rang = true }
            return true
        })
        reporter = made
        var completions = 0

        made.handleVoIPPush(twilioPayload) { completions += 1 }

        XCTAssertFalse(rang)
        // BOREAL_DIALER_v830_DIALER_CONTROLS - the ringing call is the same call: never rejected.
        XCTAssertEqual(invite.rejected, 0)
        XCTAssertEqual(provider.reported.count, 1)
        XCTAssertNotEqual(provider.reported.first?.uuid, invite.uuid,
                          "a placeholder never reuses the UUID of the call already ringing")
        XCTAssertEqual(completions, 0)

        provider.answerLast()

        XCTAssertEqual(provider.ended.first?.reason, .unanswered)
        XCTAssertEqual(completions, 1)
    }

    @MainActor
    func testInviteWhileBusyIsRejectedReportedAndEndedUnanswered() {
        let invite = FakeInvite(callSid: "CA-2")
        var reporter: CallKitReporter?
        var rang = false
        let (made, provider) = makeReporter(busy: true, twilio: { _ in
            let decision = reporter?.receive(invite: invite, firstDelivery: true) { _ in rang = true }
            XCTAssertEqual(decision, .rejectBusy)
            return true
        })
        reporter = made
        var completions = 0

        made.handleVoIPPush(twilioPayload) { completions += 1 }
        provider.answerLast()

        XCTAssertFalse(rang)
        XCTAssertEqual(invite.rejected, 1)
        XCTAssertEqual(provider.reported.count, 1)
        XCTAssertEqual(provider.ended.first?.reason, .unanswered)
        XCTAssertEqual(completions, 1)
    }

    @MainActor
    func testCallKitRefusingTheRingStillCompletesThePush() {
        let invite = FakeInvite()
        var reporter: CallKitReporter?
        var accepted: Bool?
        let (made, provider) = makeReporter(twilio: { _ in
            reporter?.receive(invite: invite, firstDelivery: true) { ringing in
                reporter?.reportRinging(uuid: ringing.uuid, handle: "", update: self.ringingUpdate()) { accepted = $0 }
            }
            return true
        })
        reporter = made
        var completions = 0

        made.handleVoIPPush(twilioPayload) { completions += 1 }
        provider.answerLast(error: NSError(domain: "CallKitReporterTests.refused", code: 3))

        XCTAssertEqual(accepted, false)
        XCTAssertEqual(completions, 1)
    }

    @MainActor
    func testCompletionRunsExactlyOnce() {
        let (reporter, provider) = makeReporter()
        var completions = 0
        reporter.handleVoIPPush([:]) { completions += 1 }
        provider.answerLast()
        provider.answerLast()
        XCTAssertEqual(completions, 1)
    }

    @MainActor
    func testPlaceholderOutsideAPushStillReportsAndEnds() {
        let (reporter, provider) = makeReporter()
        reporter.reportPlaceholder(handle: "+14165550123", reason: .unanswered)
        provider.answerLast()
        XCTAssertEqual(provider.reported.count, 1)
        XCTAssertEqual(provider.ended.first?.reason, .unanswered)
    }

    func testPushManagerReportsWithoutAnAsyncHop() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Voice/PushManager.swift"), encoding: .utf8)
        let handler = source.components(separatedBy: "didReceiveIncomingPushWith").last ?? ""
        XCTAssertTrue(handler.contains("CallKitReporter.shared.handleVoIPPush"))
        XCTAssertFalse(handler.contains("DispatchQueue.main.async"))
        XCTAssertFalse(handler.contains("defer { completion.call() }"))
    }
}
