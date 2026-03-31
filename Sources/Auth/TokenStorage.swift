import Foundation

final class TokenStorage {
    static let shared = TokenStorage()

    private let key = "auth_token"

    private init() {}

    func setToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: key)
    }

    func getToken() -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
