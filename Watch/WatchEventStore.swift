import Foundation
import UserNotifications
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@MainActor
final class WatchEventStore: NSObject, ObservableObject {
    static let shared = WatchEventStore()
    @Published private(set) var events: [WatchEvent] = []
    @Published private(set) var companionCall: WatchEvent?
    @Published private(set) var route: WatchDestination = .home
    private let maximumEvents = 25
    private override init() { super.init() }

    func startCompanionOptimization() {
#if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self; WCSession.default.activate()
        // BOREAL_DIALER_WATCH_AUTOLINK_v341 - consume any durable code already waiting.
        handle(WCSession.default.receivedApplicationContext)
#endif
    }
    func ingest(_ event: WatchEvent) {
        if let index = events.firstIndex(where: { $0.callId == event.callId && $0.kind == event.kind }) {
            events[index] = event
        } else {
            events.insert(event, at: 0)
            if events.count > maximumEvents { events.removeLast(events.count - maximumEvents) }
        }
        if event.kind == .incomingCall { companionCall = event }
        if event.kind == .missedCall, companionCall?.callId == event.callId { companionCall = nil }
    }
    // BOREAL_DIALER_WATCH_ENROLL_DELIVERY_v173 - surfaced on the root view so a
    // failed pairing is visible instead of silent.
    @Published var lastLinkError: String?
    // BOREAL_DIALER_WATCH_FACE_v371 - set by a complication tap, cleared on back.
    @Published var complicationTarget: String?

    func routeNotification(_ userInfo: [AnyHashable: Any]) { route = WatchNotificationRouter.route(userInfo: userInfo) }
    func sendCompanionAction(_ action: WatchAction) {
        guard let call = companionCall else { return }
#if canImport(WatchConnectivity)
        let payload = WatchPayload.encode(WatchActionMessage(action: action, callId: call.callId), under: WatchPayload.actionKey)
        guard !payload.isEmpty, WCSession.default.activationState == .activated else { return }
        WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
#endif
        companionCall = nil
    }
    // BOREAL_DIALER_WATCH_INCALL_v1 - relayed to the phone, which holds the
    // conference and participant ids the mute endpoint requires.
    func sendInCallControl(_ control: WatchInCallControl, digits: String? = nil) {
        guard let call = companionCall else { return }
#if canImport(WatchConnectivity)
        let payload = WatchPayload.encode(
            WatchInCallMessage(control: control, callId: call.callId, digits: digits),
            under: WatchPayload.inCallKey)
        guard !payload.isEmpty, WCSession.default.activationState == .activated else { return }
        WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
#endif
    }

    func clearSensitiveData() { events.removeAll(); companionCall = nil; route = .home }
}

#if canImport(WatchConnectivity)
extension WatchEventStore: WCSessionDelegate {
    // BOREAL_DIALER_WATCH_AUTOLINK_v341 - pull a code when the session comes alive.
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard error == nil, state == .activated else { return }
        handle(session.receivedApplicationContext)
        Task { @MainActor in
            guard await WatchAuthService.shared.token == nil else { return }
            guard session.isReachable || session.isCompanionAppInstalled else { return }
            session.sendMessage([WatchPayload.enrollRequestKey: true]) { reply in
                WatchEventStore.shared.handleFromPhone(reply)
            } errorHandler: { _ in }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) { handle(userInfo) }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) { handle(context) }
    nonisolated func handleFromPhone(_ message: [String: Any]) { handle(message) }
    nonisolated private func handle(_ message: [String: Any]) {
        // BOREAL_DIALER_WATCH_AUTOLINK_v1 - phone pushed an enrollment code; link silently.
        if let enroll = WatchPayload.decode(WatchEnrollMessage.self, from: message, key: WatchPayload.enrollKey) {
            Task { @MainActor in
                // BOREAL_DIALER_WATCH_ENROLL_DELIVERY_v173 - record the outcome.
                // This was `try?`, so a rejected or expired code failed in
                // total silence: the wrist kept rendering its local UI while
                // every authenticated request returned an error, which reads to
                // the user as "paired but nothing works".
                guard await WatchAuthService.shared.token == nil else { return }
                do {
                    try await WatchAuthService.shared.link(oneTimeCode: enroll.oneTimeCode)
                    WatchEventStore.shared.lastLinkError = nil
                } catch {
                    WatchEventStore.shared.lastLinkError =
                        (error as? WatchServiceError)?.safeMessage ?? "Pairing failed"
                }
            }
            return
        }
        guard let event = WatchPayload.decode(WatchEvent.self, from: message, key: WatchPayload.eventKey) else { return }
        Task { @MainActor in WatchEventStore.shared.ingest(event) }
    }
}
#endif
