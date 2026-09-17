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

    // BOREAL_DIALER_WATCH_AUTOLINK_v1 - push the enrollment code to the wrist so it links itself.
    // BOREAL_DIALER_WATCH_ENROLL_DELIVERY_v173
    // This returned Void and dropped the code silently whenever the session was
    // not yet activated - which is the normal state at app foreground, because
    // activate() completes asynchronously. The caller then armed its re-mint
    // rate limit as though the code had been delivered, so the next attempt was
    // suppressed for four minutes while the code itself expired in five. The
    // wrist could therefore never link. Reporting delivery lets the caller only
    // arm that limit when something actually went out.
    // BOREAL_DIALER_WATCH_LINK_TRUTH_v340
    // This reported success as soon as the session was activated. But
    // transferUserInfo is a silent no-op unless the phone also believes a watch
    // is PAIRED and that the Boreal watch app is INSTALLED on it - and a watch
    // app side-loaded from Xcode frequently is not registered as the companion
    // of the installed phone app, so isWatchAppInstalled reads false on a watch
    // you are looking at. The code went nowhere, the caller was told it had
    // been delivered, and the wrist sat on "Waiting for iPhone…" forever with
    // nothing on either device explaining why.
    @discardableResult
    public func sendEnrollment(_ code: String) -> Bool {
        guard let session else { return false }
        // Activation is idempotent; calling it here costs nothing and closes the
        // window where the very first foreground finds the session inactive.
        if session.activationState != .activated {
            activate()
            return false
        }
        let payload = WatchPayload.encode(WatchEnrollMessage(oneTimeCode: code), under: WatchPayload.enrollKey)
        guard !payload.isEmpty else { return false }
        // BOREAL_DIALER_WATCH_AUTOLINK_v341 - persist the latest code until the
        // Watch app becomes available, while retaining immediate delivery.
        var context = payload
        context["boreal.watch.enroll.at"] = Date().timeIntervalSince1970
        try? session.updateApplicationContext(context)
        if session.isPaired, session.isWatchAppInstalled { session.transferUserInfo(payload) }
        return true
    }

    // BOREAL_DIALER_WATCH_LINK_TRUTH_v340 - what the phone actually believes, in
    // words, so a failed link names its own cause instead of being guessed at.
    public func linkDiagnostics() -> String {
        guard let session else { return "This iPhone does not support Apple Watch connectivity." }
        if session.activationState != .activated { return "Still connecting to your Apple Watch. Try again in a moment." }
        if !session.isPaired { return "No Apple Watch is paired with this iPhone." }
        return "Ready. Open Boreal on your Watch and it will link itself."
    }
#else
    public func activate() {}
    public func send(_ event: WatchEvent) {}
    // BOREAL_DIALER_WATCH_ENROLL_DELIVERY_v173 - signature matches the real one.
    @discardableResult
    public func sendEnrollment(_ code: String) -> Bool { false }
    // BOREAL_DIALER_WATCH_LINK_TRUTH_v340
    public func linkDiagnostics() -> String { "Apple Watch connectivity is unavailable on this device." }
#endif
}

#if canImport(WatchConnectivity)
extension WatchBridge: WCSessionDelegate {
    // BOREAL_DIALER_WATCH_ENROLL_DELIVERY_v173
    // Activation completes asynchronously, so the foreground enrollment attempt
    // can run before the session is usable. Rather than wait for the user to
    // foreground the app a second time, retry the moment the session is ready.
    nonisolated public func session(_ session: WCSession,
                                    activationDidCompleteWith state: WCSessionActivationState,
                                    error: Error?) {
        guard error == nil, state == .activated else { return }
        Task { @MainActor in
            await WatchEnrollment.shared.enrollWatchIfNeeded()
        }
    }

    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    // BOREAL_DIALER_WATCH_AUTOLINK_v341 - mint and return a code on demand.
    nonisolated public func session(_ session: WCSession,
                                    didReceiveMessage message: [String: Any],
                                    replyHandler: @escaping ([String: Any]) -> Void) {
        guard message[WatchPayload.enrollRequestKey] != nil else {
            self.session(session, didReceiveMessage: message)
            replyHandler([:])
            return
        }
        Task { @MainActor in
            do {
                let code = try await WatchEnrollment.shared.mintCode()
                replyHandler(WatchPayload.encode(WatchEnrollMessage(oneTimeCode: code), under: WatchPayload.enrollKey))
            } catch { replyHandler([:]) }
        }
    }

    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // BOREAL_DIALER_WATCH_INCALL_v1 - the wrist asked for mute or a digit.
        // The phone owns the conference and participant ids these endpoints
        // need; the Watch only knows a callId.
        if let control = WatchPayload.decode(WatchInCallMessage.self, from: message,
                                             key: WatchPayload.inCallKey) {
            Task { @MainActor in await InCallControlRelay.shared.perform(control) }
            return
        }
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
