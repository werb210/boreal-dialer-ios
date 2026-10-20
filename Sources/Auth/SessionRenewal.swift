// BOREAL_DIALER_v831_DIALER_POLISH - staying signed in, and knowing whose session it is.
//
// A staff sign-in lasts 7 days and nothing renewed it, so staff were signed out every week - often discovered when a
// call didn't ring. When the app opens and its sign-in has under 2 days left, it now asks BF-Server for a fresh one
// (POST /auth/session/renew, which only works while the current one is still valid).
import Foundation

/// Reads claims from the staff JWT. Only for local decisions (whose queue an item is, when to renew); the server
/// checks the signature.
enum JWTClaims {
    static func payload(of token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count > 1 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func subject(of token: String?) -> String? {
        guard let token, let raw = payload(of: token)?["sub"] else { return nil }
        let sub = (raw as? String) ?? "\(raw)"
        return sub.isEmpty ? nil : sub
    }

    static func role(of token: String?) -> String? {
        guard let token else { return nil }
        return payload(of: token)?["role"] as? String
    }

    static func expiry(of token: String?) -> Date? {
        guard let token, let exp = payload(of: token)?["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

enum SessionRenewal {
    /// Renew once the sign-in has less than this left.
    static let renewWithin: TimeInterval = 2 * 24 * 3600

    static func shouldRenew(expiry: Date?, now: Date = Date()) -> Bool {
        guard let expiry else { return false }
        return expiry > now && expiry.timeIntervalSince(now) < renewWithin
    }

    private static var renewing = false
    private static let lock = NSLock()

    /// Synchronous so the lock is never held across an await.
    private static func setRenewing(_ value: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if value && renewing { return false }
        renewing = value
        return true
    }

    /// Called when the app becomes active. Never signs anyone out: a refused renewal leaves the current sign-in to run
    /// out as before.
    static func renewIfNeeded() async {
        guard let token = TokenStorage.shared.getToken(), !token.isEmpty,
              shouldRenew(expiry: JWTClaims.expiry(of: token)) else { return }
        guard setRenewing(true) else { return }
        defer { _ = setRenewing(false) }
        do {
            let request = try APIClient.shared.makeRequest(path: "/auth/session/renew", method: "POST", body: Data("{}".utf8))
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            struct Envelope: Decodable { struct Body: Decodable { let token: String }; let data: Body }
            let fresh = try JSONDecoder().decode(Envelope.self, from: data).data.token
            // Same person only: a renewal must never switch accounts.
            guard !fresh.isEmpty, let before = JWTClaims.subject(of: token), JWTClaims.subject(of: fresh) == before else { return }
            TokenStorage.shared.save(token: fresh)
            DialerEventLog.shared.record("session_renewed")
        } catch {
            DialerEventLog.shared.record("session_renew_failed", metadata: ["error": error.localizedDescription])
        }
    }
}
