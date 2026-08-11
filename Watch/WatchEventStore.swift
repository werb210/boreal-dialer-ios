// BOREAL_DIALER_WATCH_v55
import Foundation
import SwiftUI
import UserNotifications
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@MainActor
final class WatchEventStore: NSObject, ObservableObject {
    static let shared = WatchEventStore()

    /// Newest first, capped: a wrist is not a call log, and an unbounded array
    /// on a device this small is a memory problem rather than a feature.
    @Published private(set) var events: [WatchEvent] = []
    @Published private(set) var pendingCall: WatchEvent?

    private let maximumEvents = 25

    private override init() { super.init() }

    func start() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
#if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
#endif
    }

    func send(_ action: WatchAction) {
        guard let call = pendingCall else { return }
#if canImport(WatchConnectivity)
        let payload = WatchPayload.encode(WatchActionMessage(action: action, callId: call.callId),
                                          under: WatchPayload.actionKey)
        if !payload.isEmpty, WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
#endif
        // Cleared locally either way. Leaving a dead Answer button on screen
        // after the phone has taken the call is worse than acting optimistically.
        pendingCall = nil
    }

    fileprivate func ingest(_ event: WatchEvent) {
        events.insert(event, at: 0)
        if events.count > maximumEvents { events.removeLast(events.count - maximumEvents) }
        if event.kind == .incomingCall { pendingCall = event }
        if event.kind == .missedCall, pendingCall?.callId == event.callId { pendingCall = nil }
        notify(event)
    }

    private func notify(_ event: WatchEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.kind == .newMessage && !event.preview.isEmpty
            ? "\(event.subtitle): \(event.preview)"
            : event.subtitle
        content.sound = event.kind == .incomingCall ? .defaultCritical : .default
        let request = UNNotificationRequest(identifier: "\(event.kind.rawValue)-\(event.callId)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

#if canImport(WatchConnectivity)
extension WatchEventStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }

    nonisolated private func handle(_ message: [String: Any]) {
        guard let event = WatchPayload.decode(WatchEvent.self, from: message,
                                              key: WatchPayload.eventKey) else { return }
        Task { @MainActor in
            // sendMessage and transferUserInfo both fire for the same event, so
            // the duplicate is dropped here rather than buzzing the wrist twice.
            guard !WatchEventStore.shared.events.contains(event) else { return }
            WatchEventStore.shared.ingest(event)
        }
    }
}
#endif
