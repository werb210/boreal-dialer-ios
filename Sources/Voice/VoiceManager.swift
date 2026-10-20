import Foundation
import TwilioVoice

enum RegistrationState {
    case unregistered
    case registering
    case registered
    case failed
}

// BOREAL_DIALER_VOICE_DEAD_CODE_v789 - VoiceManager owns the Twilio access
// token, the VoIP push registration and presence. Calls are handled by
// TwilioVoiceManager / VoiceEngine / CallKitReporter; this class's own copy of
// the incoming-call handling (its CallDelegate and NotificationDelegate, invite
// map and accept/reject methods) was never wired to anything and is gone.
@MainActor
final class VoiceManager: NSObject, ObservableObject {

    static let shared = VoiceManager()

    @Published private(set) var registrationState: RegistrationState = .unregistered {
        // BOREAL_DIALER_v830_DIALER_CONTROLS - when this phone stopped being able to receive calls (nil while it can).
        didSet {
            if registrationState == .registered {
                notReceivingSince = nil
            } else if notReceivingSince == nil {
                notReceivingSince = Date()
            }
        }
    }
    // BOREAL_DIALER_v830_DIALER_CONTROLS - drives the "You won't receive calls" banner (CallReadinessBanner).
    @Published private(set) var notReceivingSince: Date? = Date()
    /// The last attempt to get calling ready failed (no token from BF-Server, or Twilio refused the registration).
    @Published private(set) var lastSetupFailed = false
    private var setupRetryTask: Task<Void, Never>?
    private var setupRetryCount = 0

    private var accessToken: String?
    private var tokenRefreshTask: Task<Void, Never>?
    private var latestToken: String?
    private var registeredToken: String?
    private var deviceToken: Data?
    // BOREAL_DIALER_VOICE_REFRESH_v789
    private var hasInitialized = false
    private var isInitializing = false
    private var reregisterAfterCurrent = false

    var currentToken: String {
        latestToken ?? ""
    }

    private override init() {
        super.init()
    }

    func reinitialize() async {
        cleanup()
        registrationState = .unregistered
        await initialize()
    }

    /// Fetches a token, registers for VoIP pushes with Twilio and starts the
    /// 50-minute token refresh. Presence "available" is sent only on the first
    /// initialize of a session, and only when no call is up.
    func initialize() async {
        guard !isInitializing else { return }
        isInitializing = true
        defer { isInitializing = false }
        guard let token = await fetchToken() else {
            // BOREAL_DIALER_v830_DIALER_CONTROLS - this used to give up silently: a launch with no signal (or a server
            // blip) left the phone unable to ring until the app was killed and reopened. Retry with backoff.
            lastSetupFailed = true
            Telemetry.event("voice_setup_failed", metadata: ["stage": "token", "attempt": "\(setupRetryCount)"])
            scheduleSetupRetry()
            return
        }
        lastSetupFailed = false
        setupRetryCount = 0
        setupRetryTask?.cancel()
        setupRetryTask = nil

        let firstInitialize = !hasInitialized
        hasInitialized = true
        accessToken = token
        // BOREAL_DIALER_v817_CALLS - the Twilio audio device is installed once,
        // by VoiceEngine (which owns CallKit and toggles it on activation).
        // Replacing it on every sign-in left the old device driving audio.
        _ = VoiceEngine.shared
        if firstInitialize {
            // BOREAL_DIALER_v817_CALLS - ask for the microphone at sign-in, not
            // in the middle of the first call.
            MicrophonePermission.requestIfNeeded()
        }
        configureIdentityIfNeeded(from: token) { [weak self] in
            guard let self else { return }
            await self.logout()
            SessionGuard.recordReason("Signed out because the calling identity changed. Please sign in again.") // v314
            await AuthService.shared.invalidateSessionAfterIdentityMismatch()
        }
        updateAccessToken(token)
        scheduleTokenRefresh()
        PushManager.shared.register()
        PushManager.shared.registerDeviceTokenWithTwilio()
        // BOREAL_DIALER_v830_DIALER_CONTROLS - no "available" here any more: it switched Busy off on every launch and
        // sign-in. The token fetch and the heartbeat (PresenceHeartbeat) keep presence current; only the Busy switch
        // posts a status.
    }

    /// BOREAL_DIALER_VOICE_REFRESH_v789 - the 50-minute refresh. It used to
    /// call initialize(), which also re-sent presence "online" in the middle of
    /// calls and restarted the refresh loop from inside itself.
    func refreshToken() async {
        guard let token = await fetchToken() else { return }
        accessToken = token
        updateAccessToken(token)
    }

    func handleNetworkReconnect() {
        // Connectivity recovery is not APNs invalidation. Keep a valid
        // registration; retry only a prior retryable failure.
        if registrationState == .failed { registrationState = .unregistered }
        attemptRegistrationIfPossible()
        recoverIfNeeded() // BOREAL_DIALER_v830_DIALER_CONTROLS
    }

    // BOREAL_DIALER_v830_DIALER_CONTROLS - make sure this phone can ring: called on foreground, on reconnect and from
    // the banner's Retry. Fetches a token if there is none, else retries a failed registration.
    func recoverIfNeeded() {
        guard AuthService.shared.isAuthenticated, registrationState != .registered else { return }
        if latestToken == nil {
            Task { await self.initialize() }
        } else {
            if registrationState == .failed { registrationState = .unregistered }
            attemptRegistrationIfPossible()
        }
    }

    private func scheduleSetupRetry() {
        guard setupRetryTask == nil else { return }
        let delays: [UInt64] = [15, 30, 60, 120, 300]
        let delay = delays[min(setupRetryCount, delays.count - 1)]
        setupRetryCount += 1
        setupRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.setupRetryTask = nil
            guard AuthService.shared.isAuthenticated, self.latestToken == nil else { return }
            await self.initialize()
        }
    }

    func updateAccessToken(_ token: String) {
        latestToken = token
        if registeredToken != token {
            registrationState = .unregistered
        }
        attemptRegistrationIfPossible()
    }

    /// `forceReregister` - PushKit handed the token over again (every launch);
    /// register it even when it matches the one already registered.
    func updateDeviceToken(_ token: Data, forceReregister: Bool = false) {
        if !forceReregister, deviceToken == token, registrationState == .registered { return }
        deviceToken = token
        if registrationState == .registering {
            reregisterAfterCurrent = true
            return
        }
        registrationState = .unregistered
        attemptRegistrationIfPossible()
    }

    private func scheduleTokenRefresh() {
        tokenRefreshTask?.cancel()
        tokenRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 50 * 60 * 1_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.refreshToken()
            }
        }
    }

    private func fetchToken() async -> String? {
        do {
            let requestURL = try APIClient.shared.url(path: "/voice/token")

            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.httpShouldHandleCookies = true
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // BOREAL_DIALER_VOICE_SILO_v789 - the token is minted for the active line.
            request.setValue(APIConfig.siloHeader(for: APIConfig.activeSilo), forHTTPHeaderField: "X-Silo")

            let data = try await AuthService.shared.performAuthorizedRequest(request)
            let response = try JSONDecoder().decode(TokenResponse.self, from: data)
            guard let token = response.token, !token.isEmpty else { return nil }
            return token
        } catch {
#if DEBUG
            print("Token fetch failed:", error)
#endif
            return nil
        }
    }

    private func attemptRegistrationIfPossible() {
        guard let token = latestToken, let deviceToken else { return }
        guard registrationState == .unregistered else { return }
        guard CallStateManager.shared.current() == .idle else { return }

        registrationState = .registering

        // BOREAL_DIALER_v529 - Twilio calls back on its own queue; state is main-actor.
        let registerWithToken: @Sendable () -> Void = {
            TwilioVoiceSDK.register(accessToken: token, deviceToken: deviceToken) { error in
                let failure = error.map { String(describing: $0) }
                Task { @MainActor in
                    VoiceManager.shared.finishRegistration(token: token, failure: failure)
                }
            }
        }

        // Re-registering the same access token needs no unregister first.
        guard let tokenToUnregister = registeredToken, tokenToUnregister != token else {
            registerWithToken()
            return
        }

        TwilioVoiceSDK.unregister(accessToken: tokenToUnregister, deviceToken: deviceToken) { _ in
            registerWithToken()
        }
    }

    /// BOREAL_DIALER_v817_CALLS - registration is skipped while a call is up
    /// and nothing retried it, so a token refreshed mid-call never registered
    /// and the phone stopped ringing. VoiceEngine calls this once the call ends.
    func retryRegistrationAfterCall() {
        if registrationState == .failed { registrationState = .unregistered }
        attemptRegistrationIfPossible()
    }

    /// BOREAL_DIALER_v529 - result of TwilioVoiceSDK.register, applied on the main actor.
    private func finishRegistration(token: String, failure: String?) {
        if let failure {
#if DEBUG
            print("Twilio push registration failed:", failure)
#endif
            registrationState = .failed
            lastSetupFailed = true // BOREAL_DIALER_v830_DIALER_CONTROLS
            Telemetry.event("voice_setup_failed", metadata: ["stage": "twilio_register", "error": String(failure.prefix(200))])
        } else {
            registeredToken = token
            registrationState = .registered
        }
        if reregisterAfterCurrent {
            reregisterAfterCurrent = false
            registrationState = .unregistered
            attemptRegistrationIfPossible()
        }
    }

    func invalidateDeviceToken(_ invalidatedToken: Data?) {
        guard let old = invalidatedToken else {
            deviceToken = nil
            registrationState = .unregistered
            return
        }
        deviceToken = nil
        let token = registeredToken ?? latestToken
        registrationState = .unregistered
        guard let token else { return }
        TwilioVoiceSDK.unregister(accessToken: token, deviceToken: old) { _ in }
    }

    func logout() async {
        tokenRefreshTask?.cancel()
        tokenRefreshTask = nil
        if let token = registeredToken ?? latestToken, let deviceToken {
            let failed: Bool = await withCheckedContinuation { continuation in
                TwilioVoiceSDK.unregister(accessToken: token, deviceToken: deviceToken) { error in
                    continuation.resume(returning: error != nil)
                }
            }
            // BOREAL_DIALER_v832_SIGNOUT_ALERTS - with no signal Twilio kept sending calls here; try again later.
            if failed { PendingSignOut.rememberTwilioUnregister(accessToken: token, deviceToken: deviceToken) }
        }
        accessToken = nil
        latestToken = nil
        registeredToken = nil
        registrationState = .unregistered
        hasInitialized = false
        setupRetryTask?.cancel() // BOREAL_DIALER_v830_DIALER_CONTROLS
        setupRetryTask = nil
        setupRetryCount = 0
        lastSetupFailed = false
        cleanup()
        IdentityManager.shared.clear()
    }

    /// Stops the token refresh. Calls are owned by TwilioVoiceManager, which
    /// LineManager disconnects itself before reinitializing.
    func cleanup() {
        tokenRefreshTask?.cancel()
        tokenRefreshTask = nil
        reregisterAfterCurrent = false
    }

    private static func noCallActive() -> Bool {
        CallStateManager.shared.current() == .idle && VoiceEngine.shared.isIdle
    }

    /// Configures the first valid voice identity. A different identity is never
    /// installed over the authenticated one; instead the caller supplies the
    /// asynchronous session teardown used for that security boundary.
    func configureIdentityIfNeeded(
        from token: String,
        onMismatch: @escaping @MainActor @Sendable () async -> Void
    ) {
        guard let identity = decodeIdentity(from: token), !identity.isEmpty else { return }

        if let existing = IdentityManager.shared.identity {
            guard existing == identity else {
                Task { @MainActor in
                    await onMismatch()
                }
                return
            }
            return
        }

        _ = IdentityManager.shared.configure(identity: identity)
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
            do {
                // BOREAL_DIALER_PRESENCE_v41 - was /voice/presence, a 404.
                let requestURL = try APIClient.shared.url(path: "/telephony/presence")

                var request = URLRequest(url: requestURL)
                request.httpMethod = "POST"
                request.httpShouldHandleCookies = true
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                // BOREAL_DIALER_VOICE_SILO_v789 - presence is per line.
                request.setValue(APIConfig.siloHeader(for: APIConfig.activeSilo), forHTTPHeaderField: "X-Silo")

                let body: [String: String] = [
                    "status": status,
                    "source": "dialer"
                ]

                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                _ = try await AuthService.shared.performAuthorizedRequest(request)
            } catch {
#if DEBUG
                print("Failed to send presence:", error)
#endif
            }
        }
    }
}

private struct TokenResponse: Decodable {
    let token: String?
}
