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

    /// Hands an eligible payload to Twilio. Returns false when Twilio rejects
    /// it. Twilio calls TwilioVoiceManager's NotificationDelegate synchronously
    /// on this queue (delegateQueue nil = main), so the invite reaches
    /// CallKitReporter before this returns. General notification types are
    /// never converted into local notifications or synthetic calls.
    /// BOREAL_DIALER_CALLKIT_REPORTER_v789 - eligibility is checked by
    /// CallKitReporter, which must still report a call when it fails.
    @discardableResult
    func handlePushPayload(_ payload: [AnyHashable: Any]) -> Bool {
        TwilioVoiceSDK.handleNotification(payload,
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
extension PushManager: PKPushRegistryDelegate { // BOREAL_DIALER_v529 - methods are nonisolated; @preconcurrency had no effect
    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didUpdate credentials: PKPushCredentials,
        for type: PKPushType
    ) {
        guard type == .voIP else { return }
        let token = credentials.token
        // BOREAL_DIALER_VOICE_RESUME_v789 - PushKit hands over the token on every
        // launch and whenever it rotates. Register it with Twilio each time, even
        // when it matches the last one, so a registration Twilio has expired or
        // dropped is renewed. VoiceManager defers until it holds an access token.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.voipPushToken = token
            VoiceManager.shared.updateDeviceToken(token, forceReregister: true)
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

        // BOREAL_DIALER_CALLKIT_REPORTER_v789
        // Report to CallKit synchronously, on the PushKit queue, before this
        // callback returns. The registry is created on .main, so this is the
        // main thread and the main actor; there is no async hop. The PushKit
        // completion is handed to CallKitReporter, which calls it only after
        // CallKit's reportNewIncomingCall callback.
        let dictionary = payload.dictionaryPayload
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                CallKitReporter.shared.handleVoIPPush(dictionary, completion: completion)
            }
        } else {
            // Defensive only: a registry on another queue still reports before
            // returning, by waiting for the main actor rather than queueing.
            let payload = VoIPPayloadSnapshot(dictionary)
            let completion = VoIPPushCompletion(completion)
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    CallKitReporter.shared.handleVoIPPush(payload.dictionary) { completion.call() }
                }
            }
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
