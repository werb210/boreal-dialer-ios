import Foundation
import PushKit
import TwilioVoice
import UserNotifications

@MainActor
final class PushManager: NSObject, PKPushRegistryDelegate {

    static let shared = PushManager()

    private var registry: PKPushRegistry?
    private var deviceToken: Data?

    var deviceTokenString: String? {
        guard let deviceToken else { return nil }
        return deviceToken.map { String(format: "%02x", $0) }.joined()
    }

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
        VoiceManager.shared.updateDeviceToken(deviceToken)
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didUpdate pushCredentials: PKPushCredentials,
                      for type: PKPushType) {
        guard type == .voIP else { return }
        deviceToken = pushCredentials.token
        registerDeviceTokenWithTwilio()
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        deviceToken = nil
        VoiceManager.shared.handleNetworkReconnect()
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      completion: @escaping () -> Void) {
        guard type == .voIP else {
            completion()
            return
        }

        handlePushPayload(payload.dictionaryPayload)
        completion()
    }

    func handlePushPayload(_ payload: [AnyHashable: Any]) {
        let normalized = payload.reduce(into: [String: Any]()) { result, item in
            result[String(describing: item.key)] = item.value
        }

        let type = normalized["type"] as? String ?? "incoming_call"

        switch type {
        case "incoming_call":
            // Existing VoIP call handling — leave unchanged
            handleIncomingCallPush(payload)

        case "client_message":
            let contactName = normalized["contactName"] as? String ?? "Client"
            let message = normalized["message"] as? String ?? "New message"
            let applicationId = normalized["applicationId"] as? String

            showLocalNotification(
                title: contactName,
                body: message,
                userInfo: ["type": "client_message", "applicationId": applicationId ?? ""]
            )

        case "stage_change":
            let company = normalized["company"] as? String ?? "Application"
            let newStage = normalized["stage"] as? String ?? "updated"
            let applicationId = normalized["applicationId"] as? String

            showLocalNotification(
                title: "Stage Update",
                body: "\(company) moved to \(newStage)",
                userInfo: ["type": "stage_change", "applicationId": applicationId ?? ""]
            )

        default:
            break
        }
    }

    private func handleIncomingCallPush(_ payload: [AnyHashable: Any]) {
        TwilioVoiceSDK.handleNotification(payload,
                                          delegate: VoiceManager.shared,
                                          delegateQueue: nil)
    }

    private func showLocalNotification(title: String, body: String, userInfo: [String: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
    }
}
