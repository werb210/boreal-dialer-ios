import Foundation

final class IdentityManager {
    static let shared = IdentityManager()
    private init() {}

    private(set) var identity: String?

    func configure(identity: String) {
        guard !identity.isEmpty else {
            fatalError("Dialer identity cannot be empty")
        }

        if let existing = self.identity {
            guard existing == identity else {
                fatalError("Dialer identity cannot change at runtime")
            }
            return
        }

        self.identity = identity
    }

    func requireIdentity() -> String {
        guard let id = identity else {
            fatalError("Dialer identity not configured")
        }
        return id
    }
}
