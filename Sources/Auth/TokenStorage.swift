import Foundation

final class TokenStorage {
    static let shared = TokenStorage()

    private let key = "token"

    private init() {}

    func save(token: String) {
        KeychainService.shared.save(token, for: key)
    }

    func getToken() -> String? {
        KeychainService.shared.load(key)
    }

    func getTokenOrFail() -> String {
        guard let token = KeychainService.shared.load(key),
              !token.isEmpty else {
            // BOREAL_DIALER_SURVIVE_FIRST_RUN_v21 - an unauthenticated request
            // should fail that request, not kill the app. The caller's 401
            // handling already covers this.
            print("[auth] token missing at request time")
            return ""
        }

        return token
    }

    func clear() {
        KeychainService.shared.delete(key)
    }
}
