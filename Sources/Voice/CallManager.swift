import Foundation

@MainActor
final class CallManager: ObservableObject {

    static let shared = CallManager()

    var state: CallState {
        switch VoiceEngine.shared.state {
        case .idle:
            return .idle
        case .dialing:
            return .dialing
        case .ringing:
            return .ringing
        case .active:
            return .active
        case .ended:
            return .ended
        case .failed:
            return .failed
        }
    }

    var activeCallUUID: UUID? {
        switch VoiceEngine.shared.state {
        case .dialing(let uuid), .ringing(let uuid), .active(let uuid):
            return uuid
        default:
            return nil
        }
    }

    var activeLine: Line {
        LineManager.shared.activeLine
    }

    var callDuration: Int {
        VoiceEngine.shared.callDuration
    }

    private init() {}

    func startCall(to number: String) {
        // BOREAL_DIALER_v817_CALLS - Twilio dials E.164 only.
        VoiceEngine.shared.startCall(to: PhoneFormat.e164(number))
    }

    func incomingCall(uuid: UUID) {
        VoiceEngine.shared.reportIncoming(uuid: uuid, handle: "Unknown")
    }

    @discardableResult
    func startIncomingCall(from number: String, uuid: UUID) -> Bool {
        guard case .idle = VoiceEngine.shared.state else { return false }
        VoiceEngine.shared.reportIncoming(uuid: uuid, handle: number)
        return true
    }

    func answerCall(uuid: UUID) {
        guard activeCallUUID == uuid else { return }
        // BOREAL_DIALER_v817_CALLS - through CallKit, which owns the audio session.
        VoiceEngine.shared.answer(uuid: uuid)
    }

    func callDidConnect() {
        guard let uuid = activeCallUUID else { return }
        VoiceEngine.shared.handleCallConnected(uuid: uuid)
    }

    func callDidFail() {
        VoiceEngine.shared.handleFailure()
    }

    func endCall() {
        // BOREAL_DIALER_v817_CALLS - end through CallKit (CXEndCallAction) so
        // no stale CallKit call is left to block the next one.
        VoiceEngine.shared.hangUp()
    }

    func endCall(uuid: UUID) {
        guard activeCallUUID == uuid else { return }
        endCall()
    }

    func syncWithServer(_ serverCalls: [RemoteCallStatus]) {
        VoiceEngine.shared.syncWithServer(serverCalls)
    }

    func forceTerminate() {
        VoiceEngine.shared.forceTerminate()
    }

    func setActiveLine(_ line: Line) {
        if let engineLine = VoiceEngine.Line(rawValue: line.id.lowercased()) {
            VoiceEngine.shared.setActiveLine(engineLine)
        }
    }
}
