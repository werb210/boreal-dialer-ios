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
        print("VoIP Token:", token)
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType) {
        CallKitManager.shared.reportIncomingCall(from: "Unknown")
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      completion: @escaping () -> Void) {
        CallKitManager.shared.reportIncomingCall(from: "Unknown")
        completion()
    }
}
