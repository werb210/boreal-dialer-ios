import Foundation
import CallKit
import AVFoundation

@MainActor
final class CallKitManager: NSObject, CXProviderDelegate {

    static let shared = CallKitManager()

    private let provider: CXProvider
    private let callController = CXCallController()

    private override init() {
        let config = CXProviderConfiguration(localizedName: "Boreal")
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.phoneNumber]

        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    func startCall(uuid: UUID, to number: String) {
        let handle = CXHandle(type: .phoneNumber, value: number)

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
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: handle)
        update.hasVideo = false

        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error {
                print("Incoming call report failed: \(error.localizedDescription)")
                return
            }

            CallManager.shared.incomingCall(uuid: uuid)
        }
    }

    func endCall(uuid: UUID) {
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)

        callController.request(transaction) { error in
            if let error {
                print("CallKit end call error: \(error.localizedDescription)")
            }
        }
    }

    func providerDidReset(_ provider: CXProvider) {
        print("CallKit provider reset")
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        VoiceService.shared.acceptCall(uuid: action.callUUID)
        CallManager.shared.callDidConnect()
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        VoiceService.shared.rejectCall(uuid: action.callUUID)
        CallManager.shared.callDidFail()
        action.fulfill()
    }
}
