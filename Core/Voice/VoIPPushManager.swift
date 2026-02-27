import Foundation
import PushKit
import TwilioVoice

final class VoIPPushManager: NSObject, ObservableObject {

    static let shared = VoIPPushManager()

    private var registry: PKPushRegistry!

    override init() {
        super.init()

        registry = PKPushRegistry(queue: DispatchQueue.main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
    }
}

extension VoIPPushManager: PKPushRegistryDelegate {

    func pushRegistry(_ registry: PKPushRegistry,
                      didUpdate pushCredentials: PKPushCredentials,
                      for type: PKPushType) {

        TwilioVoiceSDK.register(
            accessToken: "TEMP_TOKEN",
            deviceToken: pushCredentials.token
        ) { error in
            if let error = error {
                print("VoIP register error:", error)
            }
        }
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      completion: @escaping () -> Void) {

        TwilioVoiceSDK.handleNotification(
            payload.dictionaryPayload,
            delegate: VoiceService.shared,
            delegateQueue: DispatchQueue.main
        )

        completion()
    }
}
