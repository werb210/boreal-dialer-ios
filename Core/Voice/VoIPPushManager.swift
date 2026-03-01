import Foundation
import PushKit
import CallKit

final class VoIPPushManager: NSObject, PKPushRegistryDelegate {

    static let shared = VoIPPushManager()

    private var registry: PKPushRegistry?

    private override init() {
        super.init()
    }

    func register() {
        registry = PKPushRegistry(queue: .main)
        registry?.delegate = self
        registry?.desiredPushTypes = [.voIP]
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didUpdate pushCredentials: PKPushCredentials,
                      for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()

        Task {
            await API.registerVoIPToken(token)
        }
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType) {
        handleIncomingPush(payload, type: type)
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      completion: @escaping () -> Void) {
        handleIncomingPush(payload, type: type)
        completion()
    }

    private func handleIncomingPush(_ payload: PKPushPayload, type: PKPushType) {
        guard type == .voIP else { return }

        guard
            let uuidString = payload.dictionaryPayload["uuid"] as? String,
            let handle = payload.dictionaryPayload["handle"] as? String,
            let uuid = UUID(uuidString: uuidString)
        else {
            return
        }

        CallKitManager.shared.reportIncomingCall(uuid: uuid, handle: handle)
    }
}
