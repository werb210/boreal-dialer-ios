import Foundation
import PushKit
import CallKit

final class VoIPPushManager: NSObject {

    static let shared = VoIPPushManager()

    private let registry = PKPushRegistry(queue: .main)

    private override init() {
        super.init()

        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
    }
}

extension VoIPPushManager: PKPushRegistryDelegate {

    func pushRegistry(_ registry: PKPushRegistry,
                      didUpdate pushCredentials: PKPushCredentials,
                      for type: PKPushType) {

        let deviceToken = pushCredentials.token.map { String(format: "%02x", $0) }.joined()

        print("VoIP Push Token: \(deviceToken)")

        // TODO: send token to BF server
        // POST /api/voice/register-voip
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didInvalidatePushTokenFor type: PKPushType) {

        print("VoIP token invalidated")
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      completion: @escaping () -> Void) {

        guard type == .voIP else {
            completion()
            return
        }

        let uuid = UUID()
        let caller = payload.dictionaryPayload["caller"] as? String ?? "Unknown"

        CallKitManager.shared.startCall(to: caller)

        completion()
    }
}
