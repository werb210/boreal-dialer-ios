import Foundation

final class TokenStorage {
    static let shared = TokenStorage()

    private let key = "token"

    private init() {}

    func save(token: String) {
        UserDefaults.standard.set(token, forKey: key)
    }

    func getToken() -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    func getTokenOrFail() -> String {
        guard let token = UserDefaults.standard.string(forKey: key),
              !token.isEmpty else {
            fatalError("TOKEN MISSING AT REQUEST TIME")
        }

        return token
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
