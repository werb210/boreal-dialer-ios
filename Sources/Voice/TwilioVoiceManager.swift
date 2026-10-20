import Foundation
import AVFoundation
import TwilioVoice
#if canImport(Sentry)
import Sentry
#endif

/// Small, SDK-independent ledger used to make retried VoIP deliveries
/// idempotent. Entries live only for the current call lifecycle.
struct CallInviteLedger {
    private(set) var callSIDs = Set<String>()

    mutating func begin(_ callSID: String) -> Bool {
        guard !callSID.isEmpty else { return false }
        return callSIDs.insert(callSID).inserted
    }

    mutating func finish(_ callSID: String) { callSIDs.remove(callSID) }
    mutating func removeAll() { callSIDs.removeAll() }
}

@MainActor
final class TwilioVoiceManager: NSObject, ObservableObject {

    static let shared = TwilioVoiceManager()

    private var activeCall: Call?
    private var pendingCallInvite: CallInvite?
    private var activeUUID: UUID?
    private(set) var activeNumber: String?
    private var callStartDate: Date?
    private var callDirection: String = "outbound"
    private var inviteLedger = CallInviteLedger()
    // BOREAL_DIALER_v829_RELIABILITY - the Twilio CallSid of the latest call. Kept after the call ends (cleanup clears
    // activeCall first), so the call log and telemetry carry the real sid instead of nil / the CallKit UUID.
    private(set) var lastCallSid: String?
    /// The CallSid of the call ringing now (telemetry for the answer tap).
    var pendingInviteSid: String? { pendingCallInvite?.callSid }

    private override init() {
        super.init()

        // BOREAL_DIALER_SURVIVE_FIRST_RUN_v21
        if IdentityManager.shared.identity == nil {
            print("[voice] TwilioVoiceManager constructed before identity was configured")
        }
    }

    // BOREAL_DIALER_JOIN_CONFERENCE_v46 - `conferenceFriendly` makes the SDK
    // leg join the conference the server built instead of placing a second call.
    func startCall(uuid: UUID, to number: String, line: VoiceEngine.Line? = nil,
                   conferenceFriendly: String? = nil) {
        // BOREAL_DIALER_v817_CALLS - a busy state machine used to return
        // silently, leaving CallKit with a call that never connected or ended.
        guard CallStateManager.shared.current() == .idle else {
            Telemetry.event("call_failed", metadata: ["error": "voice state not idle"])
            VoiceEngine.shared.handleFailure()
            return
        }

        // BOREAL_DIALER_v817_CALLS - Twilio dials E.164 only.
        let dialled = PhoneFormat.e164(number)
        lastCallSid = nil // BOREAL_DIALER_v829_RELIABILITY
        CallStateManager.shared.transition(to: .connecting)
        activeUUID = uuid
        activeNumber = dialled
        callStartDate = Date()
        callDirection = "outbound"

        configureAudioSessionForCall()

        Task {
            do {
                // Capture the selected line when the call is created; a later UI
                // selection cannot change this call's attribution/token.
                let token = try await API.getTwilioToken(line: line ?? VoiceEngine.shared.activeLine)
                // BOREAL_DIALER_v817_CALLS - the call was hung up or failed while
                // the token was being fetched: do not connect a call nobody wants.
                guard self.activeUUID == uuid else { return }
                var connectParams: [String: String] = ["To": dialled]
                if let conferenceFriendly, !conferenceFriendly.isEmpty {
                    connectParams["conferenceFriendly"] = conferenceFriendly
                }
                let options = ConnectOptions(accessToken: token) { builder in
                    builder.params = connectParams
                    // BOREAL_DIALER_v817_CALLS - the SDK call must carry the
                    // CallKit UUID, or connect/disconnect callbacks cannot be
                    // matched to the CallKit call and it is never reported.
                    builder.uuid = uuid
                }

                activeCall = TwilioVoiceSDK.connect(options: options, delegate: self)
            } catch {
                await MainActor.run {
                    CallStateManager.shared.transition(to: .ended)
                    CallStateManager.shared.reset()
                    Telemetry.event("call_failed", metadata: ["error": error.localizedDescription])
#if canImport(Sentry)
                    SentrySDK.capture(error: error)
#endif
                    VoiceEngine.shared.handleFailure()
                }
            }
        }
    }

    /// BOREAL_DIALER_v829_RELIABILITY - false when there was nothing to answer (the caller already hung up, or the
    /// ring went elsewhere); the answer used to "succeed" silently into a call with no audio.
    @discardableResult
    func accept() -> Bool {
        guard CallStateManager.shared.current() == .ringing else {
            Telemetry.event("answer_without_invite", metadata: ["state": "\(CallStateManager.shared.current())"])
            // The caller must not keep hearing ringback for an answer that failed here.
            pendingCallInvite?.reject()
            pendingCallInvite = nil
            return false
        }

        CallStateManager.shared.transition(to: .connecting)

        if let invite = pendingCallInvite {
            activeUUID = invite.uuid
            activeNumber = invite.from
            callStartDate = Date()
            callDirection = "inbound"

            configureAudioSessionForCall()

            lastCallSid = invite.callSid
            activeCall = invite.accept(with: self)
            pendingCallInvite = nil
            return true
        }

        // BOREAL_DIALER_SDK_AND_ISOLATION_v5 - no pending invite means there is
        // nothing to answer; Call has no accept(). Put the state machine back.
        CallStateManager.shared.reset()
        Telemetry.event("answer_without_invite", metadata: ["state": "no_invite"])
        return false
    }

    func reject() {
        // BOREAL_DIALER_SDK_AND_ISOLATION_v5 - reject applies to an invite. An
        // already-connected call is hung up, not rejected.
        if let invite = pendingCallInvite {
            invite.reject()
            pendingCallInvite = nil
            return
        }

        activeCall?.disconnect()
    }

    @discardableResult
    func setMuted(_ muted: Bool) -> Bool {
        guard let activeCall else { return false }
        activeCall.isMuted = muted
        return activeCall.isMuted
    }

    @discardableResult
    func setOnHold(_ held: Bool) -> Bool {
        guard let activeCall else { return false }
        activeCall.isOnHold = held
        return activeCall.isOnHold
    }

    @discardableResult
    func sendDigits(_ digits: String) -> Bool {
        guard let activeCall, !digits.isEmpty else { return false }
        activeCall.sendDigits(digits)
        return true
    }

    func disconnect() {
        if let invite = pendingCallInvite {
            invite.reject()
        }

        activeCall?.disconnect()
        cleanup()
    }

    private func appendCallLog() {
        let startedAt = callStartDate ?? Date()
        let duration = max(0, Date().timeIntervalSince(startedAt))

        let log = CallLog(
            id: activeUUID ?? UUID(),
            callSid: activeCall?.sid,
            direction: callDirection,
            timestamp: startedAt,
            duration: duration
        )

        CallLogStore.shared.add(log)
    }

    private func resetCallTracking() {
        activeCall = nil
        pendingCallInvite = nil
        activeUUID = nil
        activeNumber = nil
        callStartDate = nil
        callDirection = "outbound"

        // BOREAL_DIALER_v817_CALLS - no setActive(false) here: CallKit owns the
        // audio session and deactivates it itself (provider didDeactivate).

        CallStateManager.shared.transition(to: .ended)
        CallStateManager.shared.reset()
    }

    // BOREAL_DIALER_v817_CALLS - category and mode only. CallKit activates the
    // session (provider didActivate) and deactivates it when the call ends;
    // activating it here as well fought CallKit and garbled call audio.
    // Internal so CallKit actions and voicemail playback can restore it.
    func configureAudioSessionForCall() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetoothHFP]
            )
        } catch {
            Telemetry.event("audio_session_config_failed", metadata: ["error": error.localizedDescription])
        }
    }

    func cleanup() {
        activeCall = nil
        pendingCallInvite = nil
        activeUUID = nil
        activeNumber = nil
        callStartDate = nil
        callDirection = "outbound"
        inviteLedger.removeAll()

        // BOREAL_DIALER_v817_CALLS - no setActive(false): CallKit deactivates
        // the audio session when the call ends.

        CallStateManager.shared.transition(to: .ended)
        CallStateManager.shared.reset()
    }
}

extension TwilioVoiceManager: @preconcurrency CallDelegate {

    func callDidStartRinging(call: Call) {
        if activeUUID == nil {
            activeUUID = call.uuid
        }
    }

    func callDidConnect(call: Call) {
        activeUUID = call.uuid
        lastCallSid = call.sid // BOREAL_DIALER_v829_RELIABILITY
        CallStateManager.shared.transition(to: .connected)
#if canImport(Sentry)
        SentrySDK.capture(message: "Call started")
#endif
        if let uuid = call.uuid {
            VoiceEngine.shared.handleCallConnected(uuid: uuid)
        }
    }

    // BOREAL_DIALER_v830_DIALER_CONTROLS - a signal drop mid-call: Twilio reconnects the media itself. Say so on the
    // call screen instead of silence that looks like the other side hung up.
    func callIsReconnecting(call: Call, error: Error) {
        VoiceEngine.shared.setReconnecting(true)
    }

    func callDidReconnect(call: Call) {
        VoiceEngine.shared.setReconnecting(false)
    }

    // BOREAL_DIALER_v831_DIALER_POLISH - Twilio's "disconnected" for a call staff already hung up can arrive after the
    // next call has started (calls are no longer refused in the moment after one ends). That late callback must not
    // end, or clear, the new call.
    private func isLateCallback(_ call: Call) -> Bool {
        guard let uuid = call.uuid, let current = VoiceEngine.shared.currentCallUUID else { return false }
        return uuid != current
    }

    func callDidDisconnect(call: Call, error: Error?) {
        if isLateCallback(call) {
            VoiceEngine.shared.publishFinishedCall(callSid: call.sid, endedEarlier: true)
            Telemetry.event("late_disconnect_ignored", callRef: call.sid)
            return
        }
        appendCallLog()

        // BOREAL_DIALER_PRESENT_DISPOSITION_v224
        // Publish the ended call rather than presenting from the voice layer;
        // CallKit and Watch paths also drive this engine without a view hierarchy.
        VoiceEngine.shared.publishFinishedCall(callSid: call.sid)

        if error == nil {
            VoiceEngine.shared.handleDisconnect()
        } else {
            Telemetry.event("call_error", metadata: ["message": error?.localizedDescription ?? "unknown",
                                                    "code": "\((error as NSError?)?.code ?? 0)"], callRef: call.sid)
#if canImport(Sentry)
            if let error {
                SentrySDK.capture(error: error)
            }
#endif
            VoiceEngine.shared.handleFailure()
        }

        resetCallTracking()
    }

    func callDidFailToConnect(call: Call, error: Error) {
        if isLateCallback(call) { return } // BOREAL_DIALER_v831_DIALER_POLISH
        // BOREAL_DIALER_v829_RELIABILITY - the Twilio error code (31xxx / 20xxx) says why; it is also shown to staff.
        let code = (error as NSError).code
        Telemetry.event("call_failed", metadata: ["error": error.localizedDescription, "code": "\(code)"], callRef: call.sid)
        VoiceEngine.shared.noteConnectFailure(code: code)
#if canImport(Sentry)
        SentrySDK.capture(error: error)
#endif
        VoiceEngine.shared.handleFailure()
        resetCallTracking()
    }
}

// BOREAL_DIALER_CALLKIT_REPORTER_v789 - lets CallKitReporter reject an invite
// without depending on the SDK type, so tests can use a fake.
extension CallInvite: IncomingCallInvite {}

extension TwilioVoiceManager: @preconcurrency NotificationDelegate {

    func callInviteReceived(callInvite: CallInvite) {
        // BOREAL_DIALER_CALLKIT_REPORTER_v789
        // Push delivery can be retried. A CallSid is the logical invite
        // identity, whereas the PushKit delivery itself has no stable ID.
        // Every outcome reports to CallKit through CallKitReporter, which this
        // runs inside synchronously: a duplicate or busy invite is rejected and
        // reported as an immediately-ended call instead of being dropped.
        let firstDelivery = inviteLedger.begin(callInvite.callSid)
        let decision = CallKitReporter.shared.receive(invite: callInvite, firstDelivery: firstDelivery) { invite in
            CallStateManager.shared.transition(to: .ringing)
            pendingCallInvite = callInvite
            lastCallSid = callInvite.callSid // BOREAL_DIALER_v829_RELIABILITY - a missed call logs its own sid
            // BOREAL_DIALER_v821 - BF-Server puts the caller's name, company, stage and contact id on the invite
            // (customParameters), so CallKit can name the caller without waiting on a lookup.
            let card = CallerCard.fromInviteParameters(callInvite.customParameters)
            VoiceEngine.shared.reportIncoming(uuid: invite.uuid, handle: invite.from ?? "Unknown",
                                              card: card) { [weak self] accepted in
                guard !accepted, let self else { return }
                // CallKit refused the call (Do Not Disturb, blocked number):
                // nothing is ringing, so the invite must not stay pending.
                if self.pendingCallInvite?.callSid == invite.callSid {
                    invite.reject()
                    self.pendingCallInvite = nil
                }
                self.inviteLedger.finish(invite.callSid)
                CallStateManager.shared.reset()
            }
        }
        if decision == .rejectSignedOut { // BOREAL_DIALER_v832_SIGNOUT_ALERTS
            inviteLedger.finish(callInvite.callSid)
            Telemetry.event("call_rejected_signed_out", callRef: callInvite.callSid)
            Task { await PendingSignOut.retryIfNeeded() } // and try again to stop these calls coming
        }
        if decision == .rejectBusy {
            inviteLedger.finish(callInvite.callSid)
            // BOREAL_DIALER_v831_DIALER_POLISH - one call at a time, but the second caller is no longer turned away
            // without a trace: a "Missed while you were on a call" alert with Call back. (The caller goes on to the
            // rest of the ring group or voicemail, as before.)
            let card = CallerCard.fromInviteParameters(callInvite.customParameters)
            MissedCallNotification.post(handle: callInvite.from ?? "", name: card?.callKitName, whileOnCall: true)
            Telemetry.event("call_waiting_missed", callRef: callInvite.callSid)
        }
    }

    // BOREAL_DIALER_MODULE_COMPILES_v4 - required by NotificationDelegate and
    // previously missing. Fires when the caller rings off before we answer.
    func cancelledCallInviteReceived(cancelledCallInvite: CancelledCallInvite, error: any Error) {
        guard pendingCallInvite?.callSid == cancelledCallInvite.callSid else { return }
        let uuid = pendingCallInvite?.uuid
        let missedHandle = pendingCallInvite?.from // BOREAL_DIALER_MISSED_CALL_ACTIONS_v239
        pendingCallInvite = nil
        inviteLedger.finish(cancelledCallInvite.callSid)
        Telemetry.event("call_invite_cancelled")
        if let uuid { VoiceEngine.shared.endReportedCall(uuid: uuid, reason: .unanswered) }
        if let missedHandle { MissedCallNotification.post(handle: missedHandle) }
        CallStateManager.shared.transition(to: .ended)
        CallStateManager.shared.reset()
    }
}
