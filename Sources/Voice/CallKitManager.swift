// Compatibility façade only. VoiceEngine is the canonical high-level call
// lifecycle and the sole owner of CXProvider. Older screens may call this type,
// but every operation is forwarded into that same lifecycle/provider.
import Foundation

@MainActor
final class CallKitManager {
    static let shared = CallKitManager()
    private init() {}

    func startCall(uuid: UUID, to number: String) {
        VoiceEngine.shared.startCall(to: number, uuid: uuid)
    }

    func reportIncomingCall(uuid: UUID, handle: String) {
        VoiceEngine.shared.reportIncoming(uuid: uuid, handle: handle)
    }

    func endCall(uuid: UUID) {
        VoiceEngine.shared.endReportedCall(uuid: uuid)
    }
}
