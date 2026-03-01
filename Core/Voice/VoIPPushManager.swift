import Foundation
import PushKit
import CallKit

final class VoIPPushManager: NSObject, PKPushRegistryDelegate {

    static let shared = VoIPPushManager()

    private var registry: PKPushRegistry?

    func configure() {
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
        handleIncomingPush(payload)
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      completion: @escaping () -> Void) {
        handleIncomingPush(payload)
        completion()
    }

    private func handleIncomingPush(_ payload: PKPushPayload) {
        let data = payload.dictionaryPayload
        guard
            let callId = data["callId"] as? String,
            let number = data["number"] as? String
        else {
            return
        }

        let uuid = UUID(uuidString: callId) ?? UUID()
        guard CallManager.shared.startIncomingCall(from: number, uuid: uuid) else {
            return
        }

        CallKitManager.shared.reportIncomingCall(uuid: uuid, number: number)
    }
}
