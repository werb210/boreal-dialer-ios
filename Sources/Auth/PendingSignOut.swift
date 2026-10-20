// BOREAL_DIALER_v832_SIGNOUT_ALERTS - finishing a sign-out that was done with no signal.
//
// Signing out tells Twilio to stop sending calls to this phone and tells BF-Server to stop sending alerts to it. With no
// signal both requests failed and nothing tried again, so the phone kept ringing and showing alerts for an account
// nobody was signed in to. What could not be sent is kept here (in the keychain) and sent when the signal returns,
// while the phone is still signed out. Calls that arrive in the meantime are turned away (CallKitReporter).
import Foundation
import TwilioVoice

struct PendingSignOutWork: Codable, Equatable {
    /// The alert-push token BF-Server still has for this phone, and the sign-in that registered it.
    var alertPushToken: String?
    var staffToken: String?
    /// The Twilio registration that still sends calls here.
    var twilioAccessToken: String?
    var voipDeviceToken: Data?
    var savedAt: Date

    var isEmpty: Bool { (alertPushToken == nil || staffToken == nil) && (twilioAccessToken == nil || voipDeviceToken == nil) }
}

enum PendingSignOut {
    private static let key = "boreal.dialer.pendingSignOut"

    /// Only a sign-in that is definitely gone counts. A locked keychain (just restarted) or a keychain read error is not
    /// "signed out" - treating it so would turn away a signed-in person's calls.
    static func isDefinitelySignedOut(_ result: KeychainService.ReadResult = KeychainService.shared.read("token")) -> Bool {
        switch result {
        case .notFound: return true
        case .found(let data): return data.isEmpty
        case .locked, .failed: return false
        }
    }
    /// A staff sign-in lasts 7 days, so nothing older can still be sent.
    static let maxAge: TimeInterval = 7 * 24 * 3600

    static func load() -> PendingSignOutWork? {
        guard let data = KeychainService.shared.loadData(key) else { return nil }
        return try? JSONDecoder().decode(PendingSignOutWork.self, from: data)
    }

    static func save(_ work: PendingSignOutWork) {
        guard !work.isEmpty, let data = try? JSONEncoder().encode(work) else { clear(); return }
        _ = KeychainService.shared.saveData(data, for: key)
    }

    static func clear() {
        KeychainService.shared.delete(key)
    }

    /// Keep the alert-push part of a sign-out that failed.
    static func rememberAlertUnregister(pushToken: String, staffToken: String) {
        var work = load() ?? PendingSignOutWork(savedAt: Date())
        work.alertPushToken = pushToken
        work.staffToken = staffToken
        work.savedAt = Date()
        save(work)
    }

    /// Keep the Twilio part of a sign-out that failed.
    static func rememberTwilioUnregister(accessToken: String, deviceToken: Data) {
        var work = load() ?? PendingSignOutWork(savedAt: Date())
        work.twilioAccessToken = accessToken
        work.voipDeviceToken = deviceToken
        work.savedAt = Date()
        save(work)
    }

    /// Twilio's access-token errors (expired / invalid); retrying with the same token cannot work.
    static func twilioTokenExpired(code: Int) -> Bool {
        (20101...20107).contains(code) || code == 20157
    }

    static func isStale(_ work: PendingSignOutWork, now: Date = Date()) -> Bool {
        now.timeIntervalSince(work.savedAt) > maxAge
    }

    /// A refused staff token (401) or an unknown push token (404) means the server already isn't sending; other
    /// statuses are tried again later.
    static func alertUnregisterIsDone(status: Int) -> Bool {
        (200..<300).contains(status) || status == 401 || status == 404
    }

    private static var running = false
    private static let lock = NSLock()
    private static func setRunning(_ value: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if value && running { return false }
        running = value
        return true
    }

    /// Sends what is left. Only while signed out: a new sign-in replaces both registrations itself.
    static func retryIfNeeded() async {
        guard var work = load() else { return }
        guard isDefinitelySignedOut() else { clear(); return }
        if isStale(work) { clear(); return }
        guard setRunning(true) else { return }
        defer { _ = setRunning(false) }

        if let pushToken = work.alertPushToken, let staffToken = work.staffToken {
            do {
                var request = try APIClient.shared.makeRequest(path: "/staff/push-token", method: "DELETE",
                                                               body: try JSONEncoder().encode(["token": pushToken]))
                request.setValue("Bearer \(staffToken)", forHTTPHeaderField: "Authorization")
                let (_, response) = try await URLSession.shared.data(for: request)
                if alertUnregisterIsDone(status: (response as? HTTPURLResponse)?.statusCode ?? 0) {
                    work.alertPushToken = nil
                    work.staffToken = nil
                }
            } catch {
                Telemetry.event("pending_signout_alerts_failed")
            }
        }

        // Someone may have signed in while the request above waited: then their own registration stands, and must not be
        // removed with the old one's token.
        guard isDefinitelySignedOut() else { clear(); return }
        if let accessToken = work.twilioAccessToken, let deviceToken = work.voipDeviceToken {
            let errorCode: Int? = await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    TwilioVoiceSDK.unregister(accessToken: accessToken, deviceToken: deviceToken) { error in
                        continuation.resume(returning: error.map { ($0 as NSError).code })
                    }
                }
            }
            if let errorCode {
                Telemetry.event("pending_signout_calls_failed", metadata: ["code": "\(errorCode)"])
                // An expired calling token can never succeed: stop trying (calls to this phone are turned away anyway).
                if twilioTokenExpired(code: errorCode) {
                    work.twilioAccessToken = nil
                    work.voipDeviceToken = nil
                }
            } else {
                work.twilioAccessToken = nil
                work.voipDeviceToken = nil
            }
        }

        guard isDefinitelySignedOut() else { clear(); return }
        if work.isEmpty {
            clear()
            Telemetry.event("pending_signout_finished")
        } else {
            save(work)
        }
    }
}
