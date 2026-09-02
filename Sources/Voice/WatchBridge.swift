// BOREAL_DIALER_WATCH_v55
// Phone side of the wrist. Everything here is best-effort: a call must never
// fail because a watch is out of range, asleep or not paired at all.
import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@MainActor
public final class WatchBridge: NSObject {
    public static let shared = WatchBridge()

    private override init() { super.init() }

#if canImport(WatchConnectivity)
    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    public func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    public func send(_ event: WatchEvent) {
        guard let session, session.activationState == .activated else { return }
        let payload = WatchPayload.encode(event, under: WatchPayload.eventKey)
        guard !payload.isEmpty else { return }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                // Unreachable between the check and the send. The transfer below
                // is the durable copy, so nothing is lost.
            }
        }
        // transferUserInfo queues rather than drops, which is what a missed call
        // needs: it is still worth seeing two minutes later.
        session.transferUserInfo(payload)
    }
#else
    public func activate() {}
    public func send(_ event: WatchEvent) {}
#endif
}

#if canImport(WatchConnectivity)
extension WatchBridge: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession,
                                    activationDidCompleteWith state: WCSessionActivationState,
                                    error: Error?) {}

    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let action = WatchPayload.decode(WatchActionMessage.self, from: message,
                                               key: WatchPayload.actionKey) else { return }
        Task { @MainActor in
            WatchBridge.shared.perform(action)
        }
    }

    @MainActor
    private func perform(_ message: WatchActionMessage) {
        // Companion mode controls the iPhone-owned Twilio call. Standalone
        // Watch calling is a separate server-bridge state machine.
        // BOREAL_DIALER_WATCH_NAME_v56 - acceptCallFromCallKit(uuid:) is the
        // method CXAnswerCallAction drives, so the wrist and the CallKit screen
        // take exactly the same route into the call.
        guard let uuid = UUID(uuidString: message.callId) else { return }
        switch message.action {
        case .answer:
            guard case .ringing(let active) = VoiceEngine.shared.state, active == uuid else { return }
            TwilioVoiceManager.shared.accept()
        case .decline:
            guard case .ringing(let active) = VoiceEngine.shared.state, active == uuid else { return }
            TwilioVoiceManager.shared.reject()
            VoiceEngine.shared.endReportedCall(uuid: uuid, reason: .declinedElsewhere)
        }
    }
}
#endif
