// BOREAL_DIALER_SMS_TYPING_v789 - typing indicators in an SMS thread, as the
// portal shows them. While staff type, BF-Server is told (at most every 1.5 s):
//   POST /api/communications/messages/typing {contactId, side: "staff"}
// and the client side is polled every 3 s:
//   GET  /api/communications/messages/typing?contactId=<id>&side=client
import Foundation
import SwiftUI

@MainActor
final class SMSTypingMonitor: ObservableObject {
    nonisolated static var sendThrottle: TimeInterval { 1.5 }
    nonisolated static var pollInterval: TimeInterval { 3 }

    @Published private(set) var clientTyping = false
    private var lastSent: Date?

    nonisolated static func shouldSend(lastSent: Date?, now: Date, interval: TimeInterval = sendThrottle) -> Bool {
        guard let lastSent else { return true }
        return now.timeIntervalSince(lastSent) >= interval
    }

    nonisolated static func typingPath(contactId: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let id = contactId.addingPercentEncoding(withAllowedCharacters: allowed) ?? contactId
        return "/communications/messages/typing?contactId=\(id)&side=client"
    }

    /// Reads {typing: true}, {isTyping}, {is_typing}, {active}, a {data: {...}}
    /// wrapper, or a non-empty list of typers. Anything else is "not typing".
    nonisolated static func isTyping(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return false }
        return isTyping(json: json)
    }

    nonisolated private static func isTyping(json: Any) -> Bool {
        if let list = json as? [Any] { return !list.isEmpty }
        guard let object = json as? [String: Any] else { return false }
        for key in ["typing", "isTyping", "is_typing", "active"] {
            if let flag = object[key] as? Bool { return flag }
            if let list = object[key] as? [Any] { return !list.isEmpty }
        }
        if let nested = object["data"] { return isTyping(json: nested) }
        return false
    }

    func userTyped(contactId: String?, draft: String, now: Date = Date()) {
        guard let contactId, !contactId.isEmpty,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Self.shouldSend(lastSent: lastSent, now: now) else { return }
        lastSent = now
        Task {
            guard let body = try? JSONSerialization.data(withJSONObject: ["contactId": contactId, "side": "staff"]),
                  let request = try? APIClient.shared.makeRequest(path: "/communications/messages/typing",
                                                                   method: "POST", body: body) else { return }
            _ = try? await APIClient.shared.makeAuthorizedRequest(request)
        }
    }

    /// Polls until the calling task is cancelled (the thread closes).
    func poll(contactId: String?) async {
        guard let contactId, !contactId.isEmpty else { return }
        while !Task.isCancelled {
            // Straight to the network: a typing state must never come from the
            // offline response cache, and is not worth writing to it every 3 s.
            if TokenStorage.shared.getToken() != nil,
               let request = try? APIClient.shared.makeRequest(path: Self.typingPath(contactId: contactId)),
               let data = try? await APIClient.shared.execute(APIClient.shared.authorizedRequest(request)) {
                clientTyping = Self.isTyping(data)
            } else {
                clientTyping = false
            }
            try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
        }
        clientTyping = false
    }
}
