import Foundation
import Combine

struct QueuedAction: Codable {
    let id: UUID
    let type: String
    let payload: Data
    let createdAt: Date
}

// BOREAL_DIALER_CONTACTS_TAB_v7 - matches POST /api/communications/sms, which
// takes the recipient and optionally the CRM contact so the message lands on
// that contact's timeline. `lineId` is gone: the silo travels in X-Silo.
// BOREAL_DIALER_BLOCK_v501_SMS_PARITY - one picture or PDF per text (MMS),
// sent to the same POST /communications/sms the portal uses (BF-Server v497).
struct SMSMediaPayload: Codable, Equatable {
    let name: String
    let contentType: String
    let dataUrl: String
}

struct SendSMSPayload: Codable {
    let to: String
    let body: String
    let contactId: String?
    var media: SMSMediaPayload? = nil
}

struct EndCallPayload: Codable {
    let uuid: String
}

// BOREAL_DIALER_OFFLINE_v303
// The old queue was never written to: nothing called enqueue, so a call outcome
// or task saved with no signal was simply lost. This keeps the exact request
// (path, body, silo) and replays it when the connection returns.
struct QueuedRequest: Codable, Equatable {
    let id: UUID
    let label: String
    let path: String
    let method: String
    let body: Data?
    let silo: String
    let createdAt: Date
    var attempts: Int
    var handedAt: Date? = nil // BOREAL_DIALER_BACKGROUND_SEND_v309 - the phone is sending it
    // BOREAL_DIALER_v831_DIALER_POLISH
    /// The staff member who saved it. Only their session sends it; it is never sent as someone else.
    var ownerId: String? = nil
    /// Why the server refused it for good. Kept (not silently dropped) so staff can see it, then retry or discard.
    var failure: String? = nil
}

// BOREAL_DIALER_v831_DIALER_POLISH - the queue is safe to use from anywhere.
// Before: flush() read the list once and wrote its own copy back after each send, so anything saved while it was
// sending was wiped (lost outcomes), two flushes could start together (sent twice), and a change the server refused
// was dropped after 10 tries without a word. Now every change to the list happens under one lock and touches items by
// id, only one flush runs at a time, every send carries the item's id as its Idempotency-Key (BF-Server v831 runs a
// resent change once), and a refused change stays in the list with the reason.
final class OfflineQueue: ObservableObject {

    static let shared = OfflineQueue()
    static let maxAttempts = 10

    private let legacyKey = "offline_queue"
    private let storageKey = "offline_requests_v303"
    private let defaults: UserDefaults
    private let tokenProvider: () -> String?
    private let lock = NSLock()
    private var flushing = false

    /// Waiting to send.
    @Published private(set) var pendingCount: Int = 0
    /// Refused by the server; shown to staff (OfflineStatusBar).
    @Published private(set) var failedItems: [QueuedRequest] = []

    // Injectable storage and session reads keep queue tests independent of simulator Keychain entitlements.
    init(defaults: UserDefaults = .standard,
         tokenProvider: @escaping () -> String? = { TokenStorage.shared.getToken() }) {
        self.defaults = defaults
        self.tokenProvider = tokenProvider
        defaults.removeObject(forKey: legacyKey)
        publish(load())
    }

    /// True for the errors URLSession raises when there is no usable connection.
    static func isOffline(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    func load() -> [QueuedRequest] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([QueuedRequest].self, from: data) else { return [] }
        return decoded
    }

    private func save(_ items: [QueuedRequest]) {
        let encoded = try? JSONEncoder().encode(items)
        defaults.set(encoded, forKey: storageKey)
        publish(items)
    }

    private func publish(_ items: [QueuedRequest]) {
        let pending = items.filter { $0.failure == nil }.count
        let failed = items.filter { $0.failure != nil }
        DispatchQueue.main.async {
            self.pendingCount = pending
            self.failedItems = failed
        }
    }

    /// The only way the stored list changes: read, change and write under the lock.
    @discardableResult
    private func mutate<T>(_ change: (inout [QueuedRequest]) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        var items = load()
        let before = items
        let result = change(&items)
        if items != before { save(items) }
        return result
    }

    /// `id` is also the Idempotency-Key. Pass the key a direct send already used, so a send that did arrive (its reply
    /// was lost) is not made twice when the queue resends it.
    func enqueue(label: String, path: String, method: String = "POST", body: Data?, id: UUID = UUID()) {
        let owner = JWTClaims.subject(of: tokenProvider())
        let silo = APIConfig.siloHeader(for: APIConfig.activeSilo)
        mutate { items in
            guard !items.contains(where: { $0.id == id }) else { return }
            items.append(QueuedRequest(
                id: id,
                label: label,
                path: path,
                method: method,
                body: body,
                silo: silo,
                createdAt: Date(),
                attempts: 0,
                ownerId: owner
            ))
        }
    }

    /// What the server's refusal means for a saved change.
    enum SendResult: Equatable { case sent, stop, retry, refused(String) }

    static func classify(_ error: Error) -> SendResult {
        if isOffline(error) { return .stop }
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized, .notAuthenticated:
                return .stop
            case .http(let status, _, _):
                // 409 request_in_progress: an earlier send of this same change is still being saved.
                if status == 409 { return .retry }
                switch BackgroundSender.outcome(for: status) {
                case .sent: return .sent
                case .retry: return .retry
                case .refused: return .refused(apiError.localizedDescription)
                }
            default:
                return .retry
            }
        }
        return .retry
    }

    private func claimFlush() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if flushing { return false }
        flushing = true
        return true
    }

    private func releaseFlush() {
        lock.lock()
        flushing = false
        lock.unlock()
    }

    /// Replays everything saved while offline, oldest first, once each per run. Stops while offline or signed out.
    func flush() async {
        guard NetworkMonitor.shared.isConnected, let token = tokenProvider(), !token.isEmpty else { return }
        guard claimFlush() else { return }
        defer { releaseFlush() }
        let me = JWTClaims.subject(of: token)

        // Saved under another sign-in: never sent as this person.
        mutate { items in items.removeAll { $0.ownerId != nil && $0.ownerId != me } }

        var tried = Set<UUID>()
        while true {
            let next: QueuedRequest? = mutate { items in
                items.first { $0.handedAt == nil && $0.failure == nil && !tried.contains($0.id) }
            }
            guard let item = next else { return }
            tried.insert(item.id)
            let result: SendResult
            do {
                var request = try APIClient.shared.makeRequest(path: item.path, method: item.method, body: item.body)
                request.setValue(item.silo, forHTTPHeaderField: "X-Silo")
                request.setValue(item.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
                _ = try await APIClient.shared.makeAuthorizedRequest(request)
                result = .sent
            } catch {
                result = Self.classify(error)
            }
            switch result {
            case .sent:
                mutate { items in items.removeAll { $0.id == item.id } }
            case .stop:
                return
            case .retry:
                mutate { items in
                    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
                    items[index].attempts += 1
                    if items[index].attempts >= Self.maxAttempts {
                        items[index].failure = "It couldn't be saved after several tries."
                    }
                }
            case .refused(let reason):
                mutate { items in
                    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
                    items[index].failure = reason
                }
                DialerEventLog.shared.record("offline_change_refused", metadata: ["label": item.label, "path": item.path])
            }
        }
    }

    /// Try a refused change again.
    func retry(_ id: UUID) {
        mutate { items in
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index].failure = nil
            items[index].attempts = 0
            items[index].handedAt = nil
        }
        Task { await flush() }
    }

    /// Give up on a refused change.
    func discard(_ id: UUID) {
        mutate { items in items.removeAll { $0.id == id } }
    }

    func clear() {
        mutate { items in items.removeAll() }
        BackgroundSender.shared.cancelAll() // BOREAL_DIALER_BACKGROUND_SEND_v309
    }

    // BOREAL_DIALER_BACKGROUND_SEND_v309 - leaving the app hands saved changes to iOS.
    func handOffToBackground() {
        guard let token = tokenProvider(), !token.isEmpty else { return }
        let me = JWTClaims.subject(of: token)
        mutate { items in
            for index in items.indices where items[index].handedAt == nil && items[index].failure == nil {
                let item = items[index]
                if let owner = item.ownerId, owner != me { continue }
                guard var request = try? APIClient.shared.makeRequest(path: item.path, method: item.method, body: nil) else { continue }
                request.setValue(item.silo, forHTTPHeaderField: "X-Silo")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue(item.id.uuidString, forHTTPHeaderField: "Idempotency-Key") // BOREAL_DIALER_v831_DIALER_POLISH
                do {
                    try BackgroundSender.shared.enqueue(id: item.id.uuidString, request: request, body: item.body ?? Data())
                    items[index].handedAt = Date()
                } catch {
                    continue
                }
            }
        }
    }

    /// Reads back what iOS sent while the app was closed.
    func reconcileBackground() {
        let results = BackgroundSender.shared.results()
        guard !results.isEmpty else { return }
        mutate { items in
            for (id, status) in results {
                guard let index = items.firstIndex(where: { $0.id.uuidString == id }) else { continue }
                switch BackgroundSender.outcome(for: status) {
                case .sent:
                    items.remove(at: index)
                case .refused:
                    // BOREAL_DIALER_v831_DIALER_POLISH - was dropped without a word.
                    items[index].handedAt = nil
                    items[index].failure = status == 409
                        ? nil
                        : APIError.http(status: status, code: nil, message: nil).localizedDescription
                case .retry:
                    items[index].handedAt = nil
                }
            }
        }
        BackgroundSender.shared.acknowledge(Array(results.keys))
    }
}
