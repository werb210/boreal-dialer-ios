// BOREAL_DIALER_v820_WATCH
// The Watch asked the nearby iPhone to place a call (Watch -> WCSession -> here). The iPhone places it exactly as the
// keypad does - VoiceEngine.startCall, i.e. a CXStartCallAction that CallKit performs and that starts the Twilio leg - so
// it is an ordinary VoIP call: audio follows iOS routing (connected AirPods, the iPhone, or the Watch), it shows on the
// Watch's in-call screen like any CallKit call, and no cellular minutes are used.
import Foundation

enum WatchPhoneCallDecision: Equatable {
    case place(String)
    case refuse(String)

    /// Pure gate so the rules are testable without CallKit.
    static func evaluate(signedIn: Bool, idle: Bool, destination: String) -> WatchPhoneCallDecision {
        guard signedIn else { return .refuse(WatchPhoneCallReply.reasonSignedOut) }
        guard idle else { return .refuse(WatchPhoneCallReply.reasonBusy) }
        guard let e164 = PhoneNumberNormalizer.normalize(destination) else {
            return .refuse(WatchPhoneCallReply.reasonInvalidNumber)
        }
        return .place(e164)
    }
}

@MainActor
enum WatchPhoneCallBridge {
    static func place(_ request: WatchPhoneCallRequest) -> WatchPhoneCallReply {
        let signedIn = AuthService.shared.isAuthenticated && TokenStorage.shared.getToken() != nil
        switch WatchPhoneCallDecision.evaluate(signedIn: signedIn, idle: !VoiceEngine.shared.isOnCall, // BOREAL_DIALER_v831_DIALER_POLISH
                                               destination: request.destination) {
        case .refuse(let reason):
            return WatchPhoneCallReply(accepted: false, reason: reason)
        case .place(let number):
            VoiceEngine.shared.startCall(to: number)
            // startCall returns without dialling when the microphone is denied or not yet granted (a permission
            // prompt cannot be answered from the wrist); report that instead of a call that never starts.
            if case .dialing = VoiceEngine.shared.state {
                Telemetry.event("watch_call_via_iphone")
                return WatchPhoneCallReply(accepted: true)
            }
            return WatchPhoneCallReply(accepted: false, reason: WatchPhoneCallReply.reasonMicrophone)
        }
    }

    /// A Reply typed on the Watch for a mirrored notification, handed over because only the iPhone holds the staff session.
    static func sendReply(_ message: WatchAlertReplyMessage) async {
        guard let payload = BorealAlertPayload(userInfo: message.userInfo),
              let target = BorealAlertReplyTarget.target(for: payload) else {
            AlertReplySender.postFailure()
            return
        }
        do { try await AlertReplySender.send(message.body, to: target) }
        catch { AlertReplySender.postFailure() }
    }
}
