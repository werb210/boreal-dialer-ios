import Foundation

final class IdentityManager {
    static let shared = IdentityManager()
    private init() {}

    private(set) var identity: String?

    func configure(identity: String) {
        self.identity = identity
    }

    func requireIdentity() -> String {
        guard let id = identity else {
            fatalError("Dialer identity not configured")
        }
        return id
    }
}
