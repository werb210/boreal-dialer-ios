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
            await API.answerCall(uuid: uuid.uuidString)
        }
    }

    func endCall(uuid: UUID) {
        Task {
            await API.endCall(uuid: uuid.uuidString)
        }
        activeCallUUIDs.remove(uuid)
    }
}
