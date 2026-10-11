import Foundation
import Security
import os

// BOREAL_DIALER_KEYCHAIN_v789
// Items were saved with the default accessibility (WhenUnlocked), so a VoIP
// push that woke the app on a locked phone could not read the session token,
// and the app treated that as "signed out". Items are now saved
// AfterFirstUnlockThisDeviceOnly, every SecItem status is checked, and a read
// that fails only because the device is locked is reported as `.locked`, never
// as a missing item.
final class KeychainService {

    enum ReadResult: Equatable {
        case found(Data)
        case notFound
        /// errSecInteractionNotAllowed: the item exists but cannot be read yet.
        case locked
        case failed(OSStatus)
    }

    static let shared = KeychainService()

    static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    /// Accounts this service writes, migrated to the current accessibility on launch.
    static let knownAccounts = ["token"]
    private static let migrationKey = "boreal.keychain.accessibility.v789"

    func save(_ value: String, for key: String) {
        saveData(Data(value.utf8), for: key)
    }

    @discardableResult
    func saveData(_ value: Data, for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: value,
            kSecAttrAccessible as String: Self.accessibility
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else {
            Self.log("SecItemUpdate", status: updateStatus, key: key)
            return false
        }

        var add = query
        add.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            Self.log("SecItemAdd", status: addStatus, key: key)
            return false
        }
        return true
    }

    func load(_ key: String) -> String? {
        guard let data = loadData(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func loadData(_ key: String) -> Data? {
        if case .found(let data) = read(key) { return data }
        return nil
    }

    func read(_ key: String) -> ReadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return Self.readResult(status: status, value: result)
    }

    /// Pure mapping from a SecItemCopyMatching outcome, kept separate for tests.
    static func readResult(status: OSStatus, value: AnyObject?) -> ReadResult {
        switch status {
        case errSecSuccess:
            if let data = value as? Data { return .found(data) }
            return .notFound
        case errSecItemNotFound:
            return .notFound
        case errSecInteractionNotAllowed:
            return .locked
        default:
            return .failed(status)
        }
    }

    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Self.log("SecItemDelete", status: status, key: key)
        }
    }

    /// Re-applies the current accessibility to items saved by older builds.
    /// Runs until it has succeeded once; a locked device leaves it for the
    /// next launch or the next time the app becomes active.
    func migrateAccessibilityIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: Self.migrationKey) else { return }
        var complete = true
        for account in Self.knownAccounts {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account
            ]
            let attributes: [String: Any] = [kSecAttrAccessible as String: Self.accessibility]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            switch status {
            case errSecSuccess, errSecItemNotFound:
                continue
            default:
                complete = false
                Self.log("SecItemUpdate(accessibility)", status: status, key: account)
            }
        }
        if complete { defaults.set(true, forKey: Self.migrationKey) }
    }

    private static let logger = Logger(subsystem: "financial.boreal.dialer", category: "keychain")

    private static func log(_ operation: String, status: OSStatus, key: String) {
        // Logged in release too: a failed save is a silent sign-out later.
        logger.error("\(operation, privacy: .public) failed for \(key, privacy: .public): \(status, privacy: .public)")
        Telemetry.event("keychain_failure", metadata: [
            "operation": operation,
            "status": "\(status)",
            "account": key
        ])
#if DEBUG
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
        print("[keychain] \(operation) failed for \(key): \(status) \(message)")
#endif
    }
}
