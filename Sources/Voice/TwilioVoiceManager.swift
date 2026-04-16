import Foundation
import AVFoundation
import TwilioVoice
#if canImport(Sentry)
import Sentry
#endif

@MainActor
final class TwilioVoiceManager: NSObject, ObservableObject {

    static let shared = TwilioVoiceManager()

    private var activeCall: Call?
    private var pendingCallInvite: CallInvite?
    private var activeUUID: UUID?
    private(set) var activeNumber: String?
    private var callStartDate: Date?
    private var callDirection: String = "outbound"

    private override init() {
        super.init()

        guard IdentityManager.shared.identity != nil else {
            fatalError("Identity not configured before Voice init")
        }
    }

    func startCall(uuid: UUID, to number: String) {
        guard CallStateManager.shared.current() == .idle else { return }

        CallStateManager.shared.transition(to: .connecting)
        activeUUID = uuid
        activeNumber = number
        callStartDate = Date()
        callDirection = "outbound"

        configureAudioSessionForCall()

        Task {
            do {
                let token = try await API.getTwilioToken(line: VoiceEngine.shared.activeLine)
                let options = ConnectOptions(accessToken: token) { builder in
                    builder.params = ["To": number]
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

        activeCall?.accept()
    }

    func reject() {
        if let invite = pendingCallInvite {
            invite.reject()
            pendingCallInvite = nil
            return
        }

        activeCall?.reject()
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
                options: [.allowBluetooth, .duckOthers]
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

extension TwilioVoiceManager: CallDelegate {

    func callDidStartRinging(_ call: Call) {
        if activeUUID == nil {
            activeUUID = call.uuid
        }
    }

    func callDidConnect(_ call: Call) {
        activeUUID = call.uuid
        CallStateManager.shared.transition(to: .connected)
        Telemetry.event("call_connected")
#if canImport(Sentry)
        SentrySDK.capture(message: "Call started")
#endif
        VoiceEngine.shared.handleCallConnected(uuid: call.uuid)
    }

    func callDidDisconnect(_ call: Call, error: Error?) {
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

    func callDidFailToConnect(_ call: Call, error: Error) {
        Telemetry.event("call_failed", metadata: ["error": error.localizedDescription])
#if canImport(Sentry)
        SentrySDK.capture(error: error)
#endif
        VoiceEngine.shared.handleFailure()
        resetCallTracking()
    }
}

extension TwilioVoiceManager: NotificationDelegate {

    func callInviteReceived(_ callInvite: CallInvite) {
        guard CallStateManager.shared.current() == .idle else {
            callInvite.reject()
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
}
