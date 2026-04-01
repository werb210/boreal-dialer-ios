import Foundation
import TwilioVoice

final class VoiceManager: NSObject {
    static let shared = VoiceManager()

    var onIncomingCall: (() -> Void)?
    var onCallRinging: (() -> Void)?
    var onCallConnected: (() -> Void)?
    var onCallDisconnected: ((Error?) -> Void)?
    var onCallConnectFailed: ((Error) -> Void)?
    var onDeviceError: ((Error) -> Void)?

    private var activeCall: Call?
    private var device: Device?
    private var accessToken: String?

    func configure(authToken: String) async throws {
        try await DialerService.shared.ensureValidToken(authToken: authToken)
        guard let token = DialerService.shared.accessToken else {
            print("Dialer error: missing token")
            return
        }
        configure(with: token)
    }

    func configure(with token: String) {
        accessToken = token
        let options = Device.Options(accessToken: token)
        device = Device(options: options, delegate: self)
    }

    @discardableResult
    func connectCall(to: String) -> Bool {
        guard let dialerToken = DialerService.shared.accessToken, !dialerToken.isEmpty else {
            print("Dialer error: missing token")
            return false
        }
        accessToken = dialerToken
        let token = dialerToken

        let connectOptions = ConnectOptions(accessToken: token) { builder in
            builder.params = ["To": to]
        }

        activeCall = TwilioVoiceSDK.connect(options: connectOptions, delegate: self)
        if activeCall != nil {
            print("[VoiceManager] call connected")
        }
        return activeCall != nil
    }

    func disconnect() {
        activeCall?.disconnect()
        activeCall = nil
    }
}

extension VoiceManager: DeviceDelegate {
    func deviceDidStartListeningForIncomingCalls(_ device: Device) {
        print("[VoiceManager] Device ready")
    }

    func device(_ device: Device, didFailToListenWithError error: Error) {
        onDeviceError?(error)
    }

    func device(_ device: Device, didReceiveIncomingCall callInvite: CallInvite) {
        onIncomingCall?()
        activeCall = callInvite.accept(with: self)
    }
}

extension VoiceManager: CallDelegate {
    func callDidStartRinging(_ call: Call) {
        onCallRinging?()
    }

    func callDidConnect(_ call: Call) {
        onCallConnected?()
    }

    func callDidFailToConnect(_ call: Call, error: Error) {
        activeCall = nil
        onCallConnectFailed?(error)
    }

    func callDidDisconnect(_ call: Call, error: Error?) {
        activeCall = nil
        print("[VoiceManager] call ended")
        onCallDisconnected?(error)
    }
}
