import AVFAudio
import Foundation

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

    private let audioSessionManager = AudioSessionManager()
    private var currentCallID: String?

    func initialize(completion: @escaping (Result<Void, Error>) -> Void) {
        if Environment.authToken.isEmpty {
            let error = NSError(domain: "missing_auth_token", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing AUTH_TOKEN environment variable"])
            callState = .failed(error.localizedDescription)
            completion(.failure(error))
            return
        }

        wireVoiceCallbacks()

        Task {
            do {
                let token = try await DialerService.shared.fetchToken(authToken: Environment.authToken)
                VoiceManager.shared.configure(with: token)
                await MainActor.run {
                    self.callState = .idle
                    completion(.success(()))
                }
            } catch {
                await MainActor.run {
                    self.callState = .failed(error.localizedDescription)
                    completion(.failure(error))
                }
            }
        }
    }

    func startCall(to number: String) {
        guard !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            callState = .failed("Destination number is empty")
            return
        }

        do {
            try audioSessionManager.configureForVoiceChatIfNeeded()
        } catch {
            callState = .failed("Audio session configuration failed: \(error.localizedDescription)")
            return
        }

        callState = .connecting

        Task {
            do {
                let callID = try await DialerService.shared.startCall(to: number, authToken: Environment.authToken)
                currentCallID = callID

                let didStart = VoiceManager.shared.connectCall(to: number)
                if !didStart {
                    throw NSError(domain: "voice_connect_failed", code: 0, userInfo: [NSLocalizedDescriptionKey: "Twilio failed to create a call session"])
                }
            } catch {
                await MainActor.run {
                    self.callState = .failed(error.localizedDescription)
                    self.audioSessionManager.deactivateSessionIfNeeded()
                }
            }
        }
    }

    func hangup() {
        VoiceManager.shared.disconnect()
        callState = .ended
        onCallEnd?()
        audioSessionManager.deactivateSessionIfNeeded()
        reportTerminalStatus(status: "completed")
    }

    private func wireVoiceCallbacks() {
        VoiceManager.shared.onIncomingCall = { [weak self] in
            self?.callState = .ringing
        }

        VoiceManager.shared.onCallRinging = { [weak self] in
            self?.callState = .ringing
        }

        VoiceManager.shared.onCallConnected = { [weak self] in
            self?.callState = .connected
            self?.onCallStart?()
        }

        VoiceManager.shared.onCallConnectFailed = { [weak self] error in
            self?.callState = .failed("Failed to connect: \(error.localizedDescription)")
            self?.audioSessionManager.deactivateSessionIfNeeded()
            self?.reportTerminalStatus(status: "failed")
        }

        VoiceManager.shared.onCallDisconnected = { [weak self] error in
            guard let self else { return }
            if let error {
                self.callState = .failed("Call disconnected with error: \(error.localizedDescription)")
                self.reportTerminalStatus(status: "failed")
            } else {
                self.callState = .ended
                self.reportTerminalStatus(status: "completed")
            }

            self.onCallEnd?()
            self.audioSessionManager.deactivateSessionIfNeeded()
        }

        VoiceManager.shared.onDeviceError = { [weak self] error in
            self?.callState = .failed("Device listen failed: \(error.localizedDescription)")
        }
    }

    private func reportTerminalStatus(status: String) {
        guard let callID = currentCallID else { return }

        Task {
            try? await DialerService.shared.sendCallStatus(status: status, callId: callID, authToken: Environment.authToken)
        }

        currentCallID = nil
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
