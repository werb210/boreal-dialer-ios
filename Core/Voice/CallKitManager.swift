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
                print("CallKit start call error: \(error.localizedDescription)")
            }
        }

        provider.reportOutgoingCall(with: uuid, startedConnectingAt: nil)
    }

    func reportIncomingCall(uuid: UUID, handle: String) {
        guard !reportedIncomingCallUUIDs.contains(uuid) else { return }

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle)
        update.hasVideo = false

        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error {
                print("Incoming call report failed: \(error.localizedDescription)")
                return
            }

            self.reportedIncomingCallUUIDs.insert(uuid)
            CallManager.shared.incomingCall(uuid: uuid)
        }
    }

    func endCall(uuid: UUID) {
        provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
        reportedIncomingCallUUIDs.remove(uuid)
    }

    func providerDidReset(_ provider: CXProvider) {
        reportedIncomingCallUUIDs.removeAll()
        print("CallKit provider reset")
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        VoiceManager.shared.acceptCallFromCallKit(uuid: action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        VoiceManager.shared.rejectCallFromCallKit(uuid: action.callUUID)
        action.fulfill()
    }
}
