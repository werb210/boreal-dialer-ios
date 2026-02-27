import Foundation
import CallKit

final class CallKitManager: NSObject {

    static let shared = CallKitManager()

    private let provider: CXProvider
    private let callController = CXCallController()

    private override init() {
        let configuration = CXProviderConfiguration(localizedName: "Boreal Financial")

        configuration.supportsVideo = false
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber]

        provider = CXProvider(configuration: configuration)

        super.init()

        provider.setDelegate(self, queue: nil)
    }

    func startCall(to number: String) {
        let handle = CXHandle(type: .phoneNumber, value: number)
        let callUUID = UUID()

        let startCallAction = CXStartCallAction(call: callUUID, handle: handle)
        let transaction = CXTransaction(action: startCallAction)

        callController.request(transaction) { error in
            if let error = error {
                print("CallKit start call error: \(error.localizedDescription)")
            }
        }

        provider.reportOutgoingCall(with: callUUID, startedConnectingAt: nil)
        provider.reportOutgoingCall(with: callUUID, connectedAt: Date())
    }

    func endCall(uuid: UUID) {
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)

        callController.request(transaction) { error in
            if let error = error {
                print("CallKit end call error: \(error.localizedDescription)")
            }
        }
    }
}

extension CallKitManager: CXProviderDelegate {

    func providerDidReset(_ provider: CXProvider) {
        print("CallKit provider reset")
    }

    func provider(_ provider: CXProvider,
                  perform action: CXStartCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider,
                  perform action: CXEndCallAction) {
        action.fulfill()
    }
}
