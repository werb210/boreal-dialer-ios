import Foundation
import TwilioVoice

final class CallManager: NSObject {

    static let shared = CallManager()

    private var accessToken: String?
    private var activeCall: Call?
    private var device: Device?

    func initialize(completion: @escaping (Bool) -> Void) {
        TokenService.shared.fetchToken { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let token):
                    self.accessToken = token
                    self.registerDevice(token: token)
                    completion(true)
                case .failure:
                    completion(false)
                }
            }
        }
    }

    private func registerDevice(token: String) {
        let options = Device.Options(accessToken: token)
        self.device = Device(options: options, delegate: self)
    }

    func startCall(to number: String) {
        guard let token = accessToken else { return }

        let connectOptions = ConnectOptions(accessToken: token) { builder in
            builder.params = ["To": number]
        }

        activeCall = TwilioVoiceSDK.connect(options: connectOptions, delegate: self)
    }

    func hangup() {
        activeCall?.disconnect()
        activeCall = nil
    }
}

extension CallManager: DeviceDelegate {
    func deviceDidStartListeningForIncomingCalls(_ device: Device) {
        print("Device ready")
    }

    func device(_ device: Device, didFailToListenWithError error: Error) {
        print("Device error:", error)
    }

    func device(_ device: Device, didReceiveIncomingCall callInvite: CallInvite) {
        activeCall = callInvite.accept(with: self)
    }
}

extension CallManager: CallDelegate {
    func callDidStartRinging(_ call: Call) {
        print("Ringing")
    }

    func callDidConnect(_ call: Call) {
        print("Connected")
    }

    func callDidDisconnect(_ call: Call, error: Error?) {
        print("Disconnected")
        activeCall = nil
    }
}
