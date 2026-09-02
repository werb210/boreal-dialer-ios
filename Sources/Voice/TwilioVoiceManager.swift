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
        guard CallStateManager.shared.current() == .idle else { return }

        CallStateManager.shared.transition(to: .connecting)
        activeUUID = uuid
        activeNumber = number
        callStartDate = Date()
        callDirection = "outbound"

        configureAudioSessionForCall()

        Task {
            do {
                // Capture the selected line when the call is created; a later UI
                // selection cannot change this call's attribution/token.
                let token = try await API.getTwilioToken(line: line ?? VoiceEngine.shared.activeLine)
                var connectParams: [String: String] = ["To": number]
                if let conferenceFriendly, !conferenceFriendly.isEmpty {
                    connectParams["conferenceFriendly"] = conferenceFriendly
                }
                let options = ConnectOptions(accessToken: token) { builder in
                    builder.params = connectParams
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

    func accept() {
        guard CallStateManager.shared.current() == .ringing else { return }

        CallStateManager.shared.transition(to: .connecting)

        if let invite = pendingCallInvite {
            activeUUID = invite.uuid
            activeNumber = invite.from
            callStartDate = Date()
            callDirection = "inbound"

            configureAudioSessionForCall()

            activeCall = invite.accept(with: self)
            pendingCallInvite = nil
            return
        }

        // BOREAL_DIALER_SDK_AND_ISOLATION_v5 - no pending invite means there is
        // nothing to answer; Call has no accept(). Put the state machine back.
        CallStateManager.shared.reset()
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

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            Telemetry.event("audio_session_deactivate_failed", metadata: ["error": error.localizedDescription])
        }

        CallStateManager.shared.transition(to: .ended)
        CallStateManager.shared.reset()
    }

    private func configureAudioSessionForCall() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetoothHFP, .duckOthers]
            )
            try session.setActive(true)
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

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [])
        } catch {
            Telemetry.event("audio_session_deactivate_failed", metadata: ["error": error.localizedDescription])
        }

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
        CallStateManager.shared.transition(to: .connected)
        Telemetry.event("call_connected")
#if canImport(Sentry)
        SentrySDK.capture(message: "Call started")
#endif
        if let uuid = call.uuid {
            VoiceEngine.shared.handleCallConnected(uuid: uuid)
        }
    }

    func callDidDisconnect(call: Call, error: Error?) {
        appendCallLog()

        if error == nil {
            VoiceEngine.shared.handleDisconnect()
        } else {
            Telemetry.event("call_error", metadata: ["message": error?.localizedDescription ?? "unknown"])
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
        Telemetry.event("call_failed", metadata: ["error": error.localizedDescription])
#if canImport(Sentry)
        SentrySDK.capture(error: error)
#endif
        VoiceEngine.shared.handleFailure()
        resetCallTracking()
    }
}

extension TwilioVoiceManager: @preconcurrency NotificationDelegate {

    func callInviteReceived(callInvite: CallInvite) {
        // Push delivery can be retried. A CallSid is the logical invite
        // identity, whereas the PushKit delivery itself has no stable ID.
        guard inviteLedger.begin(callInvite.callSid) else {
            callInvite.reject()
            return
        }
        guard CallStateManager.shared.current() == .idle else {
            callInvite.reject()
            inviteLedger.finish(callInvite.callSid)
            return
        }

        CallStateManager.shared.transition(to: .ringing)
        pendingCallInvite = callInvite

        let uuid = callInvite.uuid
        let handle = callInvite.from ?? "Unknown"

        DispatchQueue.main.async {
            guard CallStateManager.shared.current() == .ringing else { return }
            VoiceEngine.shared.reportIncoming(uuid: uuid, handle: handle)
        }
    }

    // BOREAL_DIALER_MODULE_COMPILES_v4 - required by NotificationDelegate and
    // previously missing. Fires when the caller rings off before we answer.
    func cancelledCallInviteReceived(cancelledCallInvite: CancelledCallInvite, error: any Error) {
        guard pendingCallInvite?.callSid == cancelledCallInvite.callSid else { return }
        let uuid = pendingCallInvite?.uuid
        pendingCallInvite = nil
        inviteLedger.finish(cancelledCallInvite.callSid)
        Telemetry.event("call_invite_cancelled")
        if let uuid { VoiceEngine.shared.endReportedCall(uuid: uuid, reason: .unanswered) }
        CallStateManager.shared.transition(to: .ended)
        CallStateManager.shared.reset()
    }
}
