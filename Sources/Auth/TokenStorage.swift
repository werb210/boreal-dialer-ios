import Foundation

final class TokenStorage {
    static let shared = TokenStorage()

    private let key = "auth_token"

    private init() {}

    func setToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: key)
    }

    func save(token: String) {
        setToken(token)
    }

    func getToken() -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    func getTokenOrFail() -> String {
        guard let token = getToken(), !token.isEmpty else {
            fatalError("NO TOKEN — REQUEST SHOULD NOT EXECUTE")
        }
        return token
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
