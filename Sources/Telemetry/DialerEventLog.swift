// BOREAL_DIALER_v829_RELIABILITY - the shipped app reported nothing: Telemetry.event printed in DEBUG builds only and
// Sentry has no DSN, so a slow or failed call left no trace. Call events (answer tapped, audio handed over, connected,
// failures, timeouts) are now kept in a small buffer and sent to BF-Server in batches
// (POST /telephony/client-events -> dialer_client_events), so a bad call can be looked up afterwards.
import Foundation

final class DialerEventLog {
    static let shared = DialerEventLog()

    static let maxPending = 200
    static let batchSize = 50
    static let flushAt = 20
    /// Sent straight away, so they are not lost if the app is closed right after.
    static let urgent: Set<String> = [
        "call_failed", "call_error", "connect_timeout", "callkit_action_timed_out",
        "call_answer_failed", "answer_without_invite", "callee_unanswered",
    ]

    private struct Entry {
        let id: UUID
        let payload: [String: Any]
    }

    private let lock = NSLock()
    private var pending: [Entry] = []
    private var flushing = false
    private static let formatter = ISO8601DateFormatter()

    private init() {}

    func record(_ name: String, metadata: [String: String] = [:], callRef: String? = nil) {
        var payload: [String: Any] = [
            "event": name,
            "at": DialerEventLog.formatter.string(from: Date()),
            "metadata": metadata,
        ]
        if let callRef, !callRef.isEmpty { payload["callRef"] = callRef }
        lock.lock()
        pending.append(Entry(id: UUID(), payload: payload))
        if pending.count > DialerEventLog.maxPending {
            pending.removeFirst(pending.count - DialerEventLog.maxPending)
        }
        let shouldFlush = pending.count >= DialerEventLog.flushAt || DialerEventLog.urgent.contains(name)
        lock.unlock()
        if shouldFlush { flush() }
    }

    /// Number of events waiting to be sent (tests and diagnostics).
    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    /// Sends up to one batch. Safe to call at any time; does nothing while signed out or already sending.
    func flush() {
        lock.lock()
        guard !flushing, !pending.isEmpty, TokenStorage.shared.getToken() != nil else {
            lock.unlock()
            return
        }
        flushing = true
        let batch = Array(pending.prefix(DialerEventLog.batchSize))
        lock.unlock()

        Task.detached(priority: .utility) {
            let delivered = await DialerEventLog.send(batch.map(\.payload))
            let sent = Set(batch.map(\.id))
            DialerEventLog.shared.finishFlush(removing: delivered ? sent : [])
        }
    }

    private func finishFlush(removing ids: Set<UUID>) {
        lock.lock()
        if !ids.isEmpty { pending.removeAll { ids.contains($0.id) } }
        flushing = false
        lock.unlock()
    }

    /// True when the server took the batch, or refused it as malformed (it would never be accepted).
    private static func send(_ events: [[String: Any]]) async -> Bool {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
            + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") + ")"
        guard let body = try? JSONSerialization.data(withJSONObject: ["appVersion": version, "events": events]) else { return true }
        do {
            let request = try APIClient.shared.makeRequest(path: "/telephony/client-events", method: "POST", body: body)
            _ = try await APIClient.shared.execute(APIClient.shared.authorizedRequest(request))
            return true
        } catch let APIError.http(status, _, _) {
            // Malformed, or the server doesn't have the route yet: never accepted, so drop it.
            return status == 400 || status == 404 || status == 405
        } catch {
            return false
        }
    }
}
