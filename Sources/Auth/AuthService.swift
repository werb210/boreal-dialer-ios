import Combine
import Foundation
import UIKit

final class AuthService: ObservableObject {

    static let shared = AuthService()

    @Published var isAuthenticated = false
    // BOREAL_DIALER_FACE_ID_SIGN_IN_v299 - set once after a text-code sign-in to offer Face ID.
    @Published var offerFaceID = false

    // BOREAL_DIALER_KEYCHAIN_v789 - true while a saved session could not be
    // read because the device was locked (errSecInteractionNotAllowed). That is
    // not "signed out": the session is re-checked when the app becomes active.
    private(set) var awaitingUnlock = false
    private var becameActiveObserver: NSObjectProtocol?

    private init() {
        KeychainService.shared.migrateAccessibilityIfNeeded()
        switch TokenStorage.shared.state() {
        case .present:
            isAuthenticated = true
        case .locked:
            isAuthenticated = true
            awaitingUnlock = true
        case .absent:
            isAuthenticated = false
        }
        becameActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            AuthService.shared.recheckAfterUnlock()
        }
    }

    /// BOREAL_DIALER_KEYCHAIN_v789 - the device is unlocked now: finish the
    /// keychain migration and settle a session that was unreadable at launch.
    func recheckAfterUnlock() {
        KeychainService.shared.migrateAccessibilityIfNeeded()
        guard awaitingUnlock else { return }
        switch TokenStorage.shared.state() {
        case .locked:
            return // still locked; try again next time
        case .present:
            awaitingUnlock = false
            resumeSavedSession()
        case .absent:
            awaitingUnlock = false
            isAuthenticated = false
        }
    }

    /// BOREAL_DIALER_VOICE_RESUME_v789 - called at launch. A saved staff session
    /// registers for VoIP pushes and starts the 50-minute token refresh straight
    /// away; before, that only happened on the next sign-in, so a relaunched app
    /// never rang.
    func resumeSavedSession() {
        guard let token = TokenStorage.shared.getToken(), !token.isEmpty else { return }
        // BOREAL_DIALER_v820_WATCH - alert pushes (missed call, voicemail, texts) reach every signed-in staff member.
        Task { @MainActor in StaffPushTokenRegistrar.shared.uploadIfNeeded() }
        guard shouldInitializeVoice(from: token) else { return }
        Task { @MainActor in
            PushManager.shared.register()
            await VoiceManager.shared.initialize()
        }
    }

    func startOTP(phone: String) async throws -> Bool {
        try await OTPService.shared.startOTP(phone: phone)
    }

    func login(phone: String, otp: String) async throws {
        let data = try await OTPService.shared.verifyOTP(phone: phone, code: otp)
        let token = try handleAuthResponse(data)

        await MainActor.run {
            self.isAuthenticated = true
            // BOREAL_DIALER_FACE_ID_SIGN_IN_v299
            let faceID = FaceIDSignIn.shared
            if faceID.biometryAvailable && !faceID.isEnrolled && !faceID.hasBeenOffered {
                faceID.markOffered()
                self.offerFaceID = true
            }
        }

        Task { await CallDirectoryManager.shared.refresh(force: true) } // BOREAL_DIALER_v831_DIALER_POLISH - a new sign-in loads caller ID now
        // BOREAL_DIALER_v820_WATCH - a new sign-in may be a different staff member: always re-register the token.
        await MainActor.run { StaffPushTokenRegistrar.shared.uploadIfNeeded(force: true) }

        if shouldInitializeVoice(from: token) {
            // BOREAL_DIALER_SDK_AND_ISOLATION_v5 - PushManager is main-actor.
            await MainActor.run { PushManager.shared.register() }
            Task {
                await VoiceManager.shared.initialize()
            }
        }
    }

    // BOREAL_DIALER_FACE_ID_SIGN_IN_v299 - same post-sign-in steps as the text code.
    func loginWithFaceID() async throws {
        let token = try await FaceIDSignIn.shared.signIn()
        TokenStorage.shared.save(token: token)
        PendingSignOut.clear() // BOREAL_DIALER_v832_SIGNOUT_ALERTS - this sign-in registers itself; the old one's leftovers go

        await MainActor.run {
            self.isAuthenticated = true
        }

        Task { await CallDirectoryManager.shared.refresh(force: true) } // BOREAL_DIALER_v831_DIALER_POLISH - a new sign-in loads caller ID now
        await MainActor.run { StaffPushTokenRegistrar.shared.uploadIfNeeded(force: true) } // BOREAL_DIALER_v820_WATCH

        if shouldInitializeVoice(from: token) {
            await MainActor.run { PushManager.shared.register() }
            Task {
                await VoiceManager.shared.initialize()
            }
        }
    }

    @discardableResult
    func handleAuthResponse(_ data: Data) throws -> String {
        let response = try JSONDecoder().decode(AuthResponse.self, from: data)

        guard response.status.lowercased() == "ok" else {
            throw APIError.invalidResponse
        }

        let token = response.data.token

        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw APIError.invalidToken
        }

        // BOREAL_DIALER_v831_DIALER_POLISH - an older server hands a non-staff number a client sign-in. Refuse it here
        // too: it "worked", the app looked normal, and the phone never rang.
        guard AuthService.isCallingRole(JWTClaims.role(of: token)) else {
            throw APIError.http(status: 403, code: "not_staff", message: nil)
        }

        TokenStorage.shared.save(token: token)
        PendingSignOut.clear() // BOREAL_DIALER_v832_SIGNOUT_ALERTS - this sign-in registers itself; the old one's leftovers go

        // BOREAL_DIALER_TESTS_v40 - removed a POST to /auth/device-token, which
        // does not exist on BF-Server. It ran on every login and 404'd silently.
        // Push registration is with Twilio, not with us: PushKit hands the token
        // to VoIPPushManager, which calls VoiceManager.updateDeviceToken, which
        // calls TwilioVoiceSDK.register. That path already works.

        return token
    }

    // BOREAL_DIALER_v831_DIALER_POLISH
    static func isCallingRole(_ role: String?) -> Bool {
        guard let role else { return false }
        return callingRoles.contains(role.trimmingCharacters(in: .whitespaces).lowercased())
    }

    private func shouldInitializeVoice(from token: String) -> Bool {
        guard let role = decodeClaim("role", from: token) else {
            return false
        }

        // BOREAL_DIALER_v817_CALLS - every staff role BF-Server issues takes
        // calls (its STAFF_ROLES: Admin, Staff, Ops, Marketing). Only admin and
        // staff were allowed, so Ops/Marketing users never registered for VoIP
        // pushes and never rang. Lender and Referrer are not staff.
        let normalized = role.trimmingCharacters(in: .whitespaces).lowercased()
        return Self.callingRoles.contains(normalized)
    }

    // BOREAL_DIALER_v817_CALLS
    private static let callingRoles: Set<String> = ["admin", "staff", "ops", "marketing"]

    private func decodeClaim(_ key: String, from token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count > 1 else { return nil }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json[key] as? String else {
            return nil
        }

        return value
    }


    func performAuthorizedRequest(_ request: URLRequest) async throws -> Data {
        try await APIClient.shared.makeAuthorizedRequest(request)
    }

    func logout() async {
        // BOREAL_DIALER_v820_WATCH - stop this account's alert pushes to this phone while the staff token still works.
        await StaffPushTokenRegistrar.shared.unregister()
        await VoiceManager.shared.logout()
        await PresenceHeartbeat.shared.goOffline()
        await FaceIDSignIn.shared.revokeAndClear() // BOREAL_DIALER_FACE_ID_SIGN_IN_v299
        ResponseCache.clear() // BOREAL_DIALER_OFFLINE_v303 - nothing from this account stays on the phone
        OfflineQueue.shared.clear()
        ContactSpotlight.clear() // BOREAL_DIALER_v593_SPOTLIGHT
        QuickReplyCache().clear() // BOREAL_DIALER_v821 - the next account must not see this one's quick replies
        await MainActor.run {
            AfterCallSummaryStore.shared.clear() // BOREAL_DIALER_v821
            CallerCardStore.shared.clear()
            VoiceEngine.shared.clearOutcomes() // BOREAL_DIALER_v831_DIALER_POLISH
        }
        await Self.clearDeviceSurfaces()
        TokenStorage.shared.clear()
        awaitingUnlock = false
        await MainActor.run { isAuthenticated = false }
    }

    // BOREAL_DIALER_LOGOUT_CLEAR_v789 - the widgets, Watch face and caller ID
    // kept showing the last account's contacts, missed calls, tasks and names
    // after sign-out. Clear every surface outside the app too.
    @MainActor
    static func clearDeviceSurfaces() async {
        WidgetSnapshotStore.clear()
        DialerDashboardStore.clear()
        StaffWidgetActionStore.clear() // BOREAL_DIALER_v823_WIDGET_ACTIONS
        WatchSnapshotSync.clear()
        WatchBridge.shared.sendClear()
        await CallDirectoryManager.shared.clearAll()
    }

    func invalidateSessionAfterIdentityMismatch() async {
        // BOREAL_DIALER_v831_DIALER_POLISH - a sign-out forced by the server (expired or revoked) only dropped the token:
        // the phone stayed registered for calls, so it kept ringing for a signed-out app, and cached contacts stayed on
        // the phone. Now it stops calls and clears what the account left on the phone. Changes saved with no signal are
        // kept: they are tagged with their owner and only that person's next sign-in sends them.
        TokenStorage.shared.clear()
        await VoiceManager.shared.logout()
        ResponseCache.clear()
        ContactSpotlight.clear()
        QuickReplyCache().clear()
        await MainActor.run {
            AfterCallSummaryStore.shared.clear()
            CallerCardStore.shared.clear()
            VoiceEngine.shared.clearOutcomes() // BOREAL_DIALER_v831_DIALER_POLISH
        }
        await Self.clearDeviceSurfaces()
        awaitingUnlock = false
        await MainActor.run { isAuthenticated = false }
    }
}
