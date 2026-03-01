import Foundation

final class CallManager {

    static let shared = CallManager()

    private var activeCallUUIDs = Set<UUID>()

    private init() {}

    @discardableResult
    func startIncomingCall(from number: String, uuid: UUID) -> Bool {
        _ = number
        guard !activeCallUUIDs.contains(uuid) else { return false }
        activeCallUUIDs.insert(uuid)
        return true
    }

    func answerCall(uuid: UUID) {
        Task {
            try? await API.answerCall(uuid: uuid.uuidString)
        }
    }

    func endCall(uuid: UUID) {
        Task {
            do {
                try await API.endCall(uuid: uuid.uuidString)
            } catch {
                guard let encoded = try? JSONEncoder().encode(EndCallPayload(uuid: uuid.uuidString)) else {
                    return
                }
                OfflineQueue.shared.enqueue(type: "end_call", payload: encoded)
            }
        }
        activeCallUUIDs.remove(uuid)
    }

    func syncWithServer(_ serverCalls: [RemoteCallStatus]) {
        let localUUIDs = Set(activeCallUUIDs)
        let serverUUIDs = Set(serverCalls.compactMap { UUID(uuidString: $0.id) })

        let stale = localUUIDs.subtracting(serverUUIDs)

        for uuid in stale {
            forceTerminate(uuid: uuid)
        }

        if localUUIDs.isEmpty,
           let ringingCall = serverCalls.first(where: { $0.status == "ringing" }),
           let ringingUUID = UUID(uuidString: ringingCall.id) {
            _ = startIncomingCall(from: ringingCall.number, uuid: ringingUUID)
            CallKitManager.shared.reportIncomingCall(uuid: ringingUUID, number: ringingCall.number)
        }
    }

    private func forceTerminate(uuid: UUID) {
        CallKitManager.shared.endCall(uuid: uuid)
        activeCallUUIDs.remove(uuid)
    }
}
