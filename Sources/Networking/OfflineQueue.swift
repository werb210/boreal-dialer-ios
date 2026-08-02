import Foundation

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

final class OfflineQueue {

    static let shared = OfflineQueue()

    private let storageKey = "offline_queue"

    private init() {}

    private var queue: [QueuedAction] {
        get {
            guard let data = UserDefaults.standard.data(forKey: storageKey),
                  let decoded = try? JSONDecoder().decode([QueuedAction].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            let encoded = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    func enqueue(type: String, payload: Data) {
        var current = queue
        current.append(
            QueuedAction(
                id: UUID(),
                type: type,
                payload: payload,
                createdAt: Date()
            )
        )
        queue = current
    }

    func flush() async {
        guard NetworkMonitor.shared.isConnected else { return }

        var remaining: [QueuedAction] = []

        for action in queue {
            do {
                try await API.executeQueuedAction(action)
            } catch {
                remaining.append(action)
            }
        }

        queue = remaining
    }
}
