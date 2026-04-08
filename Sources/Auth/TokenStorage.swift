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
            fatalError("TOKEN MISSING AT REQUEST TIME")
        }

        return token
    }

    func clear() {
        KeychainService.shared.delete(key)
    }
}
