import Foundation
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

    private override init() {
        super.init()
    }

    func startCall(uuid: UUID, to number: String) {
        activeUUID = uuid
        activeNumber = number

        Task {
            do {
                let token = try await API.getTwilioToken(line: VoiceEngine.shared.activeLine)
                let options = ConnectOptions(accessToken: token) { builder in
                    builder.params = ["To": number]
                }

                activeCall = TwilioVoiceSDK.connect(options: options, delegate: self)
            } catch {
                await MainActor.run {
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
        if let invite = pendingCallInvite {
            activeUUID = invite.uuid
            activeNumber = invite.from
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
            pendingCallInvite = nil
        }

        activeCall?.disconnect()
        activeCall = nil
        activeUUID = nil
        activeNumber = nil
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
        Telemetry.event("call_connected")
#if canImport(Sentry)
        SentrySDK.capture(message: "Call started")
#endif
        VoiceEngine.shared.handleCallConnected(uuid: call.uuid)
    }

    func callDidDisconnect(_ call: Call, error: Error?) {
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

        activeCall = nil
        activeUUID = nil
        activeNumber = nil
    }

    func callDidFailToConnect(_ call: Call, error: Error) {
        Telemetry.event("call_failed", metadata: ["error": error.localizedDescription])
#if canImport(Sentry)
        SentrySDK.capture(error: error)
#endif
        VoiceEngine.shared.handleFailure()
        activeCall = nil
        activeUUID = nil
        activeNumber = nil
    }
}

extension TwilioVoiceManager: NotificationDelegate {

    func callInviteReceived(_ callInvite: CallInvite) {
        pendingCallInvite = callInvite

        let uuid = callInvite.uuid
        let handle = callInvite.from ?? "Unknown"

        VoiceEngine.shared.reportIncoming(uuid: uuid, handle: handle)
    }
}
