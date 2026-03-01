import Foundation
import TwilioVoice
import AVFoundation

enum RegistrationState {
    case unregistered
    case registering
    case registered
}

@MainActor
final class VoiceManager: NSObject, ObservableObject {

    static let shared = VoiceManager()

    @Published private(set) var activeCall: Call?
    @Published private(set) var registrationState: RegistrationState = .unregistered

    private var accessToken: String?
    private var tokenRefreshTask: Task<Void, Never>?
    private var inviteUUIDMap: [UUID: CallInvite] = [:]
    private var pendingInvite: CallInvite?
    private var latestToken: String?
    private var registeredToken: String?
    private var deviceToken: Data?
    private var hasRequestedMicrophonePermission = false

    var currentToken: String {
        latestToken ?? ""
    }

    private override init() {
        super.init()
    }

    func initialize() async {
        guard let token = await fetchToken() else { return }

        accessToken = token
        updateAccessToken(token)
        scheduleTokenRefresh()
        TwilioVoiceSDK.audioDevice = DefaultAudioDevice()
        requestMicrophonePermissionIfNeeded()
        configureIdentityIfNeeded(from: token)
        PushManager.shared.registerDeviceTokenWithTwilio()
        sendPresence(status: "online")
    }

    func acceptCallFromCallKit() {
        guard CallStateManager.shared.current() == .ringing else { return }
        guard let invite = pendingInvite else { return }

        CallStateManager.shared.transition(to: .connecting)
        configureAudioSessionForCall()

        activeCall = invite.accept(with: self)
        pendingInvite = nil
        inviteUUIDMap = inviteUUIDMap.filter { $0.value.callSid != invite.callSid }
        sendPresence(status: "busy")
    }

    func endActiveCall() {
        activeCall?.disconnect()
        pendingInvite?.reject()
        transitionToIdleState()
    }

    func acceptCallFromCallKit(uuid: UUID) {
        guard let invite = inviteUUIDMap[uuid] else { return }
        pendingInvite = invite
        acceptCallFromCallKit()
    }

    func rejectCallFromCallKit(uuid: UUID) {
        if let invite = inviteUUIDMap[uuid] {
            invite.reject()
            inviteUUIDMap.removeValue(forKey: uuid)
            if pendingInvite?.callSid == invite.callSid {
                pendingInvite = nil
            }
        }
        endActiveCall()
    }

    func handleNetworkReconnect() {
        registrationState = .unregistered
        PushManager.shared.registerDeviceTokenWithTwilio()
    }

    func updateAccessToken(_ token: String) {
        latestToken = token
        if registeredToken != token {
            registrationState = .unregistered
        }
        attemptRegistrationIfPossible()
    }

    func updateDeviceToken(_ token: Data) {
        deviceToken = token
        registrationState = .unregistered
        attemptRegistrationIfPossible()
    }

    private func scheduleTokenRefresh() {
        tokenRefreshTask?.cancel()
        tokenRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50 * 60 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.initialize()
            }
        }
    }

    private func fetchToken() async -> String? {
        let baseURL = await MainActor.run { LineManager.shared.activeLine.baseURL }
        let url = baseURL.appendingPathComponent("api/voice/token")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let data = try await AuthService.shared.performAuthorizedRequest(request)
            let response = try JSONDecoder().decode(TokenResponse.self, from: data)
            return response.token
        } catch {
            print("Token fetch failed:", error)
            return nil
        }
    }

    func startCall(clientId: String) async {
        guard CallStateManager.shared.current() == .idle else { return }
        guard activeCall == nil else { return }
        guard clientId == IdentityManager.shared.requireIdentity() else { return }
        guard let token = accessToken else { return }

        CallStateManager.shared.transition(to: .connecting)
        configureAudioSessionForCall()

        let options = ConnectOptions(accessToken: token) { builder in
            builder.params = ["clientId": clientId]
        }

        activeCall = TwilioVoiceSDK.connect(options: options, delegate: self)
        sendPresence(status: "busy")
    }

    func acceptCall(invite: CallInvite) {
        guard CallStateManager.shared.current() == .ringing else { return }

        CallStateManager.shared.transition(to: .connecting)
        configureAudioSessionForCall()

        activeCall = invite.accept(with: self)
        pendingInvite = nil
        sendPresence(status: "busy")
    }

    func rejectCall(invite: CallInvite) {
        invite.reject()
        if pendingInvite?.uuid == invite.uuid {
            pendingInvite = nil
        }
    }

    private func attemptRegistrationIfPossible() {
        guard let token = latestToken, let deviceToken else { return }
        guard registrationState == .unregistered else { return }
        guard CallStateManager.shared.current() == .idle else { return }

        registrationState = .registering

        let registerWithToken = {
            TwilioVoiceSDK.register(withAccessToken: token, deviceToken: deviceToken) { [weak self] error in
                guard let self else { return }
                if let error {
                    print("Twilio push registration failed:", error)
                    self.registrationState = .unregistered
                    return
                }

                self.registeredToken = token
                self.registrationState = .registered
            }
        }

        let tokenToUnregister = registeredToken ?? latestToken ?? ""
        if tokenToUnregister.isEmpty {
            registerWithToken()
            return
        }

        TwilioVoiceSDK.unregister(withAccessToken: tokenToUnregister, deviceToken: deviceToken) { _ in
            registerWithToken()
        }
    }


    private func configureAudioSessionForCall() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .duckOthers])
            try session.setActive(true)
        } catch {
            print("Audio session config failed:", error)
        }
    }

    func cleanup() {
        activeCall = nil
        pendingInvite = nil
        inviteUUIDMap.removeAll()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [])
        } catch {
            print("Audio session deactivate failed:", error)
        }
    }

    private func transitionToIdleState() {
        activeCall = nil
        pendingInvite = nil
        inviteUUIDMap.removeAll()
        sendPresence(status: "online")
    }

    private func requestMicrophonePermissionIfNeeded() {
        guard !hasRequestedMicrophonePermission else { return }
        hasRequestedMicrophonePermission = true
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }

    private func configureIdentityIfNeeded(from token: String) {
        guard let identity = decodeIdentity(from: token), !identity.isEmpty else { return }

        if let existing = IdentityManager.shared.identity {
            guard existing == identity else {
                fatalError("Dialer identity mismatch: \(existing) != \(identity)")
            }
            return
        }

        IdentityManager.shared.configure(identity: identity)
    }

    private func decodeIdentity(from token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count > 1 else { return nil }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard
            let data = Data(base64Encoded: base64),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let grants = json["grants"] as? [String: Any],
            let identity = grants["identity"] as? String
        else {
            return nil
        }

        return identity
    }

    func sendPresence(status: String) {
        Task {
            let baseURL = await MainActor.run { LineManager.shared.activeLine.baseURL }
            let url = baseURL.appendingPathComponent("api/voice/presence")

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpShouldHandleCookies = true
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: String] = [
                "status": status,
                "source": "dialer"
            ]

            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await AuthService.shared.performAuthorizedRequest(request)
        }
    }
}

extension VoiceManager: CallDelegate {

    func callDidStartRinging(_ call: Call) {
        print("Ringing")
    }

    func callDidConnect(_ call: Call) {
        print("Connected")
        CallStateManager.shared.transition(to: .connected)
        sendPresence(status: "busy")
        notifyServerStatus(status: "connected")
    }

    func callDidDisconnect(_ call: Call, error: Error?) {
        print("Disconnected")
        if let uuid = inviteUUIDMap.first(where: { $0.value.callSid == call.sid })?.key {
            CallKitManager.shared.endCall(uuid: uuid)
            inviteUUIDMap.removeValue(forKey: uuid)
        }

        CallStateManager.shared.transition(to: .ended)
        transitionToIdleState()
        cleanup()
        CallStateManager.shared.reset()
        notifyServerStatus(status: "completed")
    }

    private func notifyServerStatus(status: String) {
        Task {
            let baseURL = await MainActor.run { LineManager.shared.activeLine.baseURL }
            let url = baseURL.appendingPathComponent("api/voice/status")

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpShouldHandleCookies = true
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = [
                "callStatus": status
            ]

            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await AuthService.shared.performAuthorizedRequest(request)
        }
    }
}

extension VoiceManager: NotificationDelegate {

    func callInviteReceived(_ callInvite: CallInvite) {
        guard CallStateManager.shared.current() == .idle else {
            callInvite.reject()
            return
        }

        if activeCall != nil || pendingInvite != nil {
            callInvite.reject()
            return
        }

        CallStateManager.shared.transition(to: .ringing)
        pendingInvite = callInvite
        let uuid = callInvite.uuid
        inviteUUIDMap[uuid] = callInvite

        DispatchQueue.main.async {
            guard CallStateManager.shared.current() == .ringing else { return }
            CallKitManager.shared.reportIncomingCall(
                uuid: uuid,
                handle: callInvite.from ?? "Incoming"
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self else { return }
            guard self.activeCall == nil else { return }
            guard self.pendingInvite?.callSid == callInvite.callSid else { return }
            self.pendingInvite?.reject()
            self.pendingInvite = nil
            CallStateManager.shared.transition(to: .ended)
            CallStateManager.shared.reset()
            self.cleanup()
        }
    }

    func cancelledCallInviteReceived(_ cancelledCallInvite: CancelledCallInvite, error: (any Error)?) {
        if pendingInvite?.callSid == cancelledCallInvite.callSid {
            pendingInvite = nil
            cleanup()
            CallStateManager.shared.transition(to: .ended)
            CallStateManager.shared.reset()
        }
        if let uuid = inviteUUIDMap.first(where: { $0.value.callSid == cancelledCallInvite.callSid })?.key {
            CallKitManager.shared.endCall(uuid: uuid)
            inviteUUIDMap.removeValue(forKey: uuid)
        }
    }
}

private struct TokenResponse: Decodable {
    let token: String
}
