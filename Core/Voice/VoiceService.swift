import Foundation
import TwilioVoice

protocol VoiceServiceProtocol {
    func startCall(to number: String)
    func endCall()
}

final class VoiceService: NSObject, VoiceServiceProtocol {

    static let shared = VoiceService()

    private let tokenProvider: TokenProvider
    private let callState = CallState()

    private var activeCall: Call?
    private var activeUUID: UUID?

    init(tokenProvider: TokenProvider = BFTokenProvider()) {
        self.tokenProvider = tokenProvider
        super.init()
    }

    func startCall(to number: String) {

        callState.status = .connecting
        callState.activeNumber = number

        activeUUID = UUID()

        Task {
            do {
                let token = try await tokenProvider.fetchAccessToken()

                let options = ConnectOptions(accessToken: token) { builder in
                    builder.params = ["To": number]
                }

                activeCall = TwilioVoiceSDK.connect(options: options, delegate: self)

                CallKitManager.shared.startCall(to: number)

            } catch {
                callState.status = .failed("Token fetch failed")
            }
        }
    }

    func endCall() {
        activeCall?.disconnect()
        callState.status = .ended
        callState.activeNumber = nil
    }

    func getCallState() -> CallState {
        callState
    }
}

extension VoiceService: CallDelegate {

    func callDidStartRinging(_ call: Call) {
        callState.status = .ringing
    }

    func callDidConnect(_ call: Call) {
        callState.status = .active
    }

    func callDidDisconnect(_ call: Call, error: Error?) {

        if let error = error {
            callState.status = .failed(error.localizedDescription)
        } else {
            callState.status = .ended
        }

        activeCall = nil
    }
}
