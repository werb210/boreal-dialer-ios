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
    func clearSensitiveData() { events.removeAll(); companionCall = nil; route = .home }
}

#if canImport(WatchConnectivity)
extension WatchEventStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) { handle(userInfo) }
    nonisolated private func handle(_ message: [String: Any]) {
        guard let event = WatchPayload.decode(WatchEvent.self, from: message, key: WatchPayload.eventKey) else { return }
        Task { @MainActor in WatchEventStore.shared.ingest(event) }
    }
}
#endif
