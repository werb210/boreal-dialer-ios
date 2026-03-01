import Foundation
import PushKit
import TwilioVoice

@MainActor
final class PushManager: NSObject, PKPushRegistryDelegate {

    static let shared = PushManager()

    private var registry: PKPushRegistry?
    private var deviceToken: Data?

    private override init() {
        super.init()
    }

    func register() {
        registry = PKPushRegistry(queue: .main)
        registry?.delegate = self
        registry?.desiredPushTypes = [.voIP]
    }

    func registerDeviceTokenWithTwilio() {
        guard let deviceToken else { return }
        let token = VoiceManager.shared.currentToken
        guard !token.isEmpty else { return }

        TwilioVoiceSDK.register(withAccessToken: token, deviceToken: deviceToken) { error in
            if let error {
                print("Twilio push registration failed:", error)
            } else {
                print("Push registration successful")
            }
        }
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didUpdate pushCredentials: PKPushCredentials,
                      for type: PKPushType) {
        guard type == .voIP else { return }
        deviceToken = pushCredentials.token
        registerDeviceTokenWithTwilio()
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      completion: @escaping () -> Void) {
        guard type == .voIP else {
            completion()
            return
        }

        TwilioVoiceSDK.handleNotification(payload.dictionaryPayload,
                                          delegate: VoiceManager.shared,
                                          delegateQueue: nil)
        completion()
    }
}
