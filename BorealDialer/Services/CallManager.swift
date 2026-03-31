import AVFAudio
import Foundation
import TwilioVoice

enum CallState: Equatable {
    case idle
    case connecting
    case ringing
    case connected
    case ended
    case failed(String)
}

final class CallManager: NSObject {

    static let shared = CallManager()

    private(set) var callState: CallState = .idle {
        didSet {
            onStateChange?(callState)
        }
    }

    var onStateChange: ((CallState) -> Void)?
    var onCallStart: (() -> Void)?
    var onCallEnd: (() -> Void)?
    var onAudioFrame: ((Data) -> Void)?
    var onTranscript: ((String) -> Void)?

    private var accessToken: String?
    private var identity: String?
    private var activeCall: Call?
    private var device: Device?
    private let audioSessionManager = AudioSessionManager()

    func initialize(completion: @escaping (Result<Void, Error>) -> Void) {
        TokenService.shared.fetchToken { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let tokenData):
                    self.accessToken = tokenData.token
                    self.identity = tokenData.identity
                    self.registerDevice(token: tokenData.token)
                    self.callState = .idle
                    completion(.success(()))
                case .failure(let error):
                    self.callState = .failed(error.localizedDescription)
                    completion(.failure(error))
                }
            }
        }
    }

    private func registerDevice(token: String) {
        let options = Device.Options(accessToken: token)
        device = Device(options: options, delegate: self)
    }

    func startCall(to number: String) {
        guard !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            callState = .failed("Destination number is empty")
            return
        }

        guard let token = accessToken else {
            callState = .failed("No token available. Initialize CallManager first.")
            return
        }

        do {
            try audioSessionManager.configureForVoiceChatIfNeeded()
        } catch {
            callState = .failed("Audio session configuration failed: \(error.localizedDescription)")
            logCallFailure(reason: "Audio session configuration failed")
            return
        }

        callState = .connecting
        logCallStart(number: number)

        let connectOptions = ConnectOptions(accessToken: token) { builder in
            builder.params = ["To": number]
        }

        activeCall = TwilioVoiceSDK.connect(options: connectOptions, delegate: self)

        if activeCall == nil {
            callState = .failed("Twilio failed to create a call session")
            logCallFailure(reason: "Twilio connect returned nil call")
        }
    }

    func hangup() {
        activeCall?.disconnect()
        activeCall = nil
        callState = .ended
        logCallEnd()
        onCallEnd?()
        audioSessionManager.deactivateSessionIfNeeded()
    }

    private func logCallStart(number: String) {
        print("[CallManager] call_start to=\(number)")
        // TODO: Forward to BF-Server call logging endpoint when available.
    }

    private func logCallEnd() {
        print("[CallManager] call_end")
        // TODO: Forward to BF-Server call logging endpoint when available.
    }

    private func logCallFailure(reason: String) {
        print("[CallManager] call_failure reason=\(reason)")
        // TODO: Forward to BF-Server call logging endpoint when available.
    }
}

extension CallManager: DeviceDelegate {
    func deviceDidStartListeningForIncomingCalls(_ device: Device) {
        print("Device ready")
    }

    func device(_ device: Device, didFailToListenWithError error: Error) {
        callState = .failed("Device listen failed: \(error.localizedDescription)")
        logCallFailure(reason: "Device listen failed: \(error.localizedDescription)")
    }

    func device(_ device: Device, didReceiveIncomingCall callInvite: CallInvite) {
        callState = .ringing
        activeCall = callInvite.accept(with: self)
    }
}

extension CallManager: CallDelegate {
    func callDidStartRinging(_ call: Call) {
        callState = .ringing
    }

    func callDidConnect(_ call: Call) {
        callState = .connected
        onCallStart?()
    }

    func callDidFailToConnect(_ call: Call, error: Error) {
        callState = .failed("Failed to connect: \(error.localizedDescription)")
        logCallFailure(reason: "Failed to connect: \(error.localizedDescription)")
        activeCall = nil
        audioSessionManager.deactivateSessionIfNeeded()
    }

    func callDidDisconnect(_ call: Call, error: Error?) {
        if let error {
            callState = .failed("Call disconnected with error: \(error.localizedDescription)")
            logCallFailure(reason: "Disconnected with error: \(error.localizedDescription)")
        } else {
            callState = .ended
            logCallEnd()
        }

        activeCall = nil
        onCallEnd?()
        audioSessionManager.deactivateSessionIfNeeded()
    }
}

final class AudioSessionManager {
    private let session = AVAudioSession.sharedInstance()
    private var isConfigured = false

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func configureForVoiceChatIfNeeded() throws {
        guard !isConfigured else { return }

        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setActive(true)
        isConfigured = true
    }

    func deactivateSessionIfNeeded() {
        guard isConfigured else { return }

        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            isConfigured = false
        } catch {
            print("[AudioSessionManager] failed to deactivate session: \(error.localizedDescription)")
        }
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let typeRaw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else {
            return
        }

        switch type {
        case .began:
            print("[AudioSessionManager] interruption began")
        case .ended:
            do {
                try session.setActive(true)
                print("[AudioSessionManager] interruption ended and audio resumed")
            } catch {
                print("[AudioSessionManager] failed to resume audio session: \(error.localizedDescription)")
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let reasonRaw = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw)
        else {
            return
        }

        print("[AudioSessionManager] audio route changed: \(reason.rawValue)")
    }
}
