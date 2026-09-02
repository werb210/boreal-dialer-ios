import Foundation
import PushKit
import TwilioVoice

/// Sole owner of the application's PushKit registry and VoIP token. Ordinary
/// APNs notifications are handled by StandardNotificationCoordinator.
@MainActor
final class PushManager: NSObject {
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
        // PushKit is not a second general-purpose notification channel.  A
        // payload must positively identify itself as a Twilio Voice call; an
        // absent/unknown `type` is not sufficient evidence.
        let applicationType = payload["type"] as? String
        guard applicationType == nil || applicationType == "incoming_call" else {
            return false
        }

        if payload["twi_call_sid"] as? String != nil { return true }
        if let messageType = payload["twi_message_type"] as? String {
            return messageType.hasPrefix("twilio.voice.call")
        }
        return false
    }
}

// PushKit is an Objective-C delegate API whose imported protocol does not yet
// express that callbacks arrive on the registry's queue. Keep the conformance
// nonisolated for that legacy contract, then explicitly enter MainActor before
// touching application state. The registry itself is configured on `.main`.
extension PushManager: @preconcurrency PKPushRegistryDelegate {
    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didUpdate credentials: PKPushCredentials,
        for type: PKPushType
    ) {
        guard type == .voIP else { return }
        let token = credentials.token
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.voipPushToken = token
            self.registerDeviceTokenWithTwilio()
        }
    }

    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didInvalidatePushTokenFor type: PKPushType
    ) {
        guard type == .voIP else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let invalidated = self.voipPushToken
            self.voipPushToken = nil
            VoiceManager.shared.invalidateDeviceToken(invalidated)
        }
    }

    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else {
            completion()
            return
        }

        // Copy the bridged NSDictionary while still in the delegate callback.
        // The box is safe to transfer because this snapshot is immutable after
        // construction; its unchecked conformance is limited to this bridge.
        let payload = VoIPPayloadSnapshot(payload.dictionaryPayload)
        let completion = VoIPPushCompletion(completion)
        Task { @MainActor [weak self] in
            defer { completion.call() }
            guard let self else { return }
            self.handlePushPayload(payload.dictionary)
        }
    }
}

private struct VoIPPushCompletion: @unchecked Sendable {
    private let callback: () -> Void

    init(_ callback: @escaping () -> Void) {
        self.callback = callback
    }

    func call() {
        callback()
    }
}

private struct VoIPPayloadSnapshot: @unchecked Sendable {
    let dictionary: [AnyHashable: Any]

    init(_ dictionary: [AnyHashable: Any]) {
        self.dictionary = dictionary
    }
}
