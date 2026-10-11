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

    /// BOREAL_DIALER_KEYCHAIN_v789 - tells "no token" apart from "the device
    /// is locked and the token cannot be read yet".
    enum State: Equatable {
        case present
        case absent
        case locked
    }

    func state() -> State {
        switch KeychainService.shared.read(key) {
        case .found(let data):
            return data.isEmpty ? .absent : .present
        case .locked:
            return .locked
        case .notFound, .failed:
            return .absent
        }
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
