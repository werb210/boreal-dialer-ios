import Foundation
import PushKit
import TwilioVoice

/// Sole owner of the application's PushKit registry and VoIP token. Ordinary
/// APNs notifications are handled by StandardNotificationCoordinator.
@MainActor
final class PushManager: NSObject, PKPushRegistryDelegate {
    static let shared = PushManager()

    private var registry: PKPushRegistry?
    private(set) var voipPushToken: Data?

    private override init() { super.init() }

    func register() {
        guard registry == nil else { return }
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.registry = registry
    }

    func registerDeviceTokenWithTwilio() {
        guard let voipPushToken else { return }
        VoiceManager.shared.updateDeviceToken(voipPushToken)
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials,
                      for type: PKPushType) {
        guard type == .voIP else { return }
        voipPushToken = credentials.token
        registerDeviceTokenWithTwilio()
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        let invalidated = voipPushToken
        voipPushToken = nil
        VoiceManager.shared.invalidateDeviceToken(invalidated)
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType, completion: @escaping () -> Void) {
        defer { completion() }
        guard type == .voIP else { return }
        handlePushPayload(payload.dictionaryPayload)
    }

    /// Returns false when Twilio rejects the payload. General notification
    /// types are never converted into local notifications or synthetic calls.
    @discardableResult
    func handlePushPayload(_ payload: [AnyHashable: Any]) -> Bool {
        guard Self.isEligibleVoIPPayload(payload) else { return false }
        return TwilioVoiceSDK.handleNotification(payload,
                                                  delegate: TwilioVoiceManager.shared,
                                                  delegateQueue: nil)
    }

    static func isEligibleVoIPPayload(_ payload: [AnyHashable: Any]) -> Bool {
        let declaredType = payload["type"] as? String
        return declaredType != "client_message" && declaredType != "stage_change"
    }
}
