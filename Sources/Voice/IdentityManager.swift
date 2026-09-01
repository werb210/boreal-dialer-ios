import Foundation

final class IdentityManager {
    static let shared = IdentityManager()
    private init() {}

    private(set) var identity: String?

    @discardableResult
    func configure(identity: String) -> Bool {
        guard !identity.isEmpty else { return false }

        if let existing = self.identity {
            return existing == identity
        }

        self.identity = identity
        return true
    }

    func requireIdentity() -> String? { identity }
    func clear() { identity = nil }
}
