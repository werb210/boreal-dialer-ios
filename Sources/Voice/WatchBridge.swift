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
        // The watch never carries audio. Answering there hands the call to the
        // phone, which is the device with the microphone and the Twilio session.
        switch message.action {
        case .answer:
            VoiceManager.shared.acceptPendingCall()
        case .decline:
            VoiceManager.shared.endActiveCall()
        }
    }
}
#endif
