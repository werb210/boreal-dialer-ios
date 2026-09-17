import Foundation

// BOREAL_DIALER_SESSION_GUARD_v314
// Any 401 from any request used to wipe the session and return to the login
// screen. A single endpoint refusing one request (a BI read against the BI
// server, a route with its own rules) therefore signed staff out "randomly",
// and a fresh Face ID sign-in bounced straight back to the login screen. Now a
// 401 only ends the session when BF-Server itself confirms, via /auth/me, that
// the token is no longer valid. The reason is kept and shown on the login
// screen, so an unexpected sign-out says which request caused it.
actor SessionGuard {
    static let shared = SessionGuard()
    private static let reasonKey = "boreal.dialer.lastSignOutReason"
    private var checking = false

    /// Called when a request returned 401. Signs out only if the session is really gone.
    func confirm(after url: URL?) async {
        guard !checking else { return }
        guard let url, Self.isMainServer(url) else { return }
        checking = true
        defer { checking = false }
        guard let token = TokenStorage.shared.getToken(), !token.isEmpty,
              let me = URL(string: APIConfig.BASE_URL + "/auth/me") else { return }
        var request = URLRequest(url: me)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(APIConfig.siloHeader(for: APIConfig.activeSilo), forHTTPHeaderField: "X-Silo")
        let status: Int
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            return // no answer is not proof the session is invalid
        }
        guard status == 401 else { return }
        Self.recordReason("Your session ended (\(url.path) was refused). Please sign in again.")
        TokenStorage.shared.clear()
        await AuthService.shared.invalidateSessionAfterIdentityMismatch()
    }

    nonisolated static func isMainServer(_ url: URL) -> Bool {
        guard let host = url.host, let main = URL(string: APIConfig.BASE_URL)?.host else { return false }
        return host == main
    }

    nonisolated static func recordReason(_ reason: String) {
        UserDefaults.standard.set(reason, forKey: reasonKey)
    }

    nonisolated static func takeLastReason() -> String? {
        let reason = UserDefaults.standard.string(forKey: reasonKey)
        UserDefaults.standard.removeObject(forKey: reasonKey)
        return reason
    }
}
