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
struct SendSMSPayload: Codable {
    let to: String
    let body: String
    let contactId: String?
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
}

final class OfflineQueue: ObservableObject {

    static let shared = OfflineQueue()
    static let maxAttempts = 10

    private let legacyKey = "offline_queue"
    private let storageKey = "offline_requests_v303"
    private let lock = NSLock()
    private var flushing = false

    @Published private(set) var pendingCount: Int = 0

    private init() {
        UserDefaults.standard.removeObject(forKey: legacyKey)
        pendingCount = load().count
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
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([QueuedRequest].self, from: data) else { return [] }
        return decoded
    }

    private func save(_ items: [QueuedRequest]) {
        let encoded = try? JSONEncoder().encode(items)
        UserDefaults.standard.set(encoded, forKey: storageKey)
        let count = items.count
        DispatchQueue.main.async { self.pendingCount = count }
    }

    func enqueue(label: String, path: String, method: String = "POST", body: Data?) {
        lock.lock()
        defer { lock.unlock() }
        var items = load()
        items.append(QueuedRequest(
            id: UUID(),
            label: label,
            path: path,
            method: method,
            body: body,
            silo: APIConfig.siloHeader(for: APIConfig.activeSilo),
            createdAt: Date(),
            attempts: 0
        ))
        save(items)
    }

    /// Replays everything saved while offline, oldest first. Stops while still offline
    /// or signed out; a request the server keeps refusing is dropped after maxAttempts.
    func flush() async {
        guard NetworkMonitor.shared.isConnected, TokenStorage.shared.getToken() != nil else { return }
        if flushing { return }
        flushing = true
        defer { flushing = false }

        var items = load()
        var index = 0
        while index < items.count {
            let item = items[index]
            if item.handedAt != nil { index += 1; continue } // v309: the phone is already sending it
            do {
                var request = try APIClient.shared.makeRequest(path: item.path, method: item.method, body: item.body)
                request.setValue(item.silo, forHTTPHeaderField: "X-Silo")
                _ = try await APIClient.shared.makeAuthorizedRequest(request)
                items.remove(at: index)
                save(items)
            } catch {
                if Self.isOffline(error) { break }
                if let apiError = error as? APIError, case .unauthorized = apiError { break }
                items[index].attempts += 1
                if items[index].attempts >= Self.maxAttempts {
                    items.remove(at: index)
                } else {
                    index += 1
                }
                save(items)
            }
        }
    }

    func clear() {
        save([])
        BackgroundSender.shared.cancelAll() // BOREAL_DIALER_BACKGROUND_SEND_v309
    }

    // BOREAL_DIALER_BACKGROUND_SEND_v309 - leaving the app hands saved changes to iOS.
    func handOffToBackground() {
        guard let token = TokenStorage.shared.getToken(), !token.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var items = load()
        var changed = false
        for index in items.indices where items[index].handedAt == nil {
            let item = items[index]
            guard var request = try? APIClient.shared.makeRequest(path: item.path, method: item.method, body: nil) else { continue }
            request.setValue(item.silo, forHTTPHeaderField: "X-Silo")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                try BackgroundSender.shared.enqueue(id: item.id.uuidString, request: request, body: item.body ?? Data())
                items[index].handedAt = Date()
                changed = true
            } catch {
                continue
            }
        }
        if changed { save(items) }
    }

    /// Reads back what iOS sent while the app was closed.
    func reconcileBackground() {
        let results = BackgroundSender.shared.results()
        guard !results.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var items = load()
        for (id, status) in results {
            guard let index = items.firstIndex(where: { $0.id.uuidString == id }) else { continue }
            switch BackgroundSender.outcome(for: status) {
            case .sent, .refused:
                items.remove(at: index)
            case .retry:
                items[index].handedAt = nil
            }
        }
        save(items)
        BackgroundSender.shared.acknowledge(Array(results.keys))
    }
}
