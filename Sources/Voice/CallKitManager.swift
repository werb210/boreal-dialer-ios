// BOREAL_DIALER_CALLKIT_IDENTITY_v38
// NOT the live CallKit provider. VoiceEngine configures and owns CXProvider and
// is what VoIPPushManager reports through; this type predates it and is kept
// only because other code still references it. Do not report calls from here -
// two providers reporting the same UUID produces duplicate incoming screens.
import Foundation
import CallKit
import AVFoundation

@MainActor
final class CallKitManager: NSObject, CXProviderDelegate {

    static let shared = CallKitManager()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var reportedIncomingCallUUIDs: Set<UUID> = []

    private override init() {
        let config = CXProviderConfiguration(localizedName: "Boreal")
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.includesCallsInRecents = true
        config.supportedHandleTypes = [.generic]

        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    func startCall(uuid: UUID, to number: String) {
        let handle = CXHandle(type: .generic, value: number)

        let startCallAction = CXStartCallAction(call: uuid, handle: handle)
        let transaction = CXTransaction(action: startCallAction)

        callController.request(transaction) { error in
            if let error {
                #if DEBUG
                print("CallKit start call error: \(error.localizedDescription)")
#endif
            }
        }

        provider.reportOutgoingCall(with: uuid, startedConnectingAt: nil)
    }

    func reportIncomingCall(uuid: UUID, handle: String) {
        // BOREAL_DIALER_WATCH_v55 - the wrist learns about the call at the same
        // moment CallKit does, not after the phone has been fished out.
        WatchBridge.shared.send(WatchEvent(kind: .incomingCall,
                                           callId: uuid.uuidString,
                                           displayName: "",
                                           handle: handle))
        guard !reportedIncomingCallUUIDs.contains(uuid) else { return }

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle)
        update.hasVideo = false

        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error {
                #if DEBUG
                print("Incoming call report failed: \(error.localizedDescription)")
#endif
                return
            }

            self.reportedIncomingCallUUIDs.insert(uuid)
            CallManager.shared.incomingCall(uuid: uuid)
        }
    }

    func endCall(uuid: UUID) {
        // BOREAL_DIALER_WATCH_v55 - clears a stale Answer button on the watch.
        WatchBridge.shared.send(WatchEvent(kind: .missedCall,
                                           callId: uuid.uuidString,
                                           displayName: "",
                                           handle: ""))
        provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
        reportedIncomingCallUUIDs.remove(uuid)
    }

    func providerDidReset(_ provider: CXProvider) {
        reportedIncomingCallUUIDs.removeAll()
        #if DEBUG
        print("CallKit provider reset")
#endif
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard CallStateManager.shared.current() == .ringing else {
            action.fail()
            return
        }

        guard CallStateManager.shared.transition(from: .ringing, to: .connecting) else {
            action.fail()
            return
        }

        VoiceManager.shared.acceptCallFromCallKit(uuid: action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        VoiceManager.shared.endActiveCall()
        CallStateManager.shared.reset()
        action.fulfill()
    }
}
