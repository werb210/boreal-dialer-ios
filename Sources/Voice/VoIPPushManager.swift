// Compatibility façade. PushManager owns the one PKPushRegistry used by the
// application; this legacy name must never create another registry/listener.
import Foundation

@MainActor
final class VoIPPushManager {
    static let shared = VoIPPushManager()
    private init() {}
    func register() { PushManager.shared.register() }
}
