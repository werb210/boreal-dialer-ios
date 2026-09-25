import Foundation
import LocalAuthentication
import Security

// BOREAL_DIALER_FACE_ID_SIGN_IN_v299
// Face ID sign-in (BF-Server v298). After a text-code sign-in the app can
// enroll: the server returns a device secret. The secret is stored in the
// Keychain with .biometryCurrentSet, so iOS itself requires Face ID to read it
// (and forgets it if Face ID is re-enrolled). The credential id is not secret
// and lives in UserDefaults so sign-out can revoke without a Face ID prompt.
enum FaceIDSignInError: Error {
    case notEnrolled
    case cancelled
    case rejected
}

// BOREAL_DIALER_v529 - only immutable String state, so it is safe to share across threads.
final class FaceIDSignIn: Sendable {
    static let shared = FaceIDSignIn()

    private let service = "com.boreal.dialer.faceid"
    private let account = "device-sign-in-secret"
    private let credentialIdKey = "boreal.faceid.credentialId"
    private let offeredKey = "boreal.faceid.offered"

    private init() {}

    var biometryAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    var credentialId: String? { UserDefaults.standard.string(forKey: credentialIdKey) }
    var isEnrolled: Bool { credentialId != nil }
    var hasBeenOffered: Bool { UserDefaults.standard.bool(forKey: offeredKey) }
    func markOffered() { UserDefaults.standard.set(true, forKey: offeredKey) }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func storeSecret(_ secret: String) -> Bool {
        SecItemDelete(baseQuery as CFDictionary)
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            nil
        ) else { return false }
        var item = baseQuery
        item[kSecValueData as String] = Data(secret.utf8)
        item[kSecAttrAccessControl as String] = access
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private func readSecret(reason: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let context = LAContext()
                context.localizedReason = reason
                var item = self.baseQuery
                item[kSecReturnData as String] = true
                item[kSecMatchLimit as String] = kSecMatchLimitOne
                item[kSecUseAuthenticationContext as String] = context
                var result: AnyObject?
                let status = SecItemCopyMatching(item as CFDictionary, &result)
                if status == errSecSuccess, let data = result as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
        UserDefaults.standard.removeObject(forKey: credentialIdKey)
    }

    private struct EnrollResponse: Decodable {
        let credentialId: String
        let secret: String
    }

    private struct SignInResponse: Decodable {
        let status: String
        let data: Payload
        struct Payload: Decodable {
            let token: String
            let secret: String
        }
    }

    /// Needs a signed-in session. Returns false (never throws) so sign-in is never blocked.
    func enroll() async -> Bool {
        guard biometryAvailable else { return false }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["deviceLabel": "Boreal Dialer iPhone"])
            let request = try APIClient.shared.makeRequest(path: "/auth/device-sign-in/enroll", method: "POST", body: body)
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            let response = try JSONDecoder().decode(EnrollResponse.self, from: data)
            guard storeSecret(response.secret) else { return false }
            UserDefaults.standard.set(response.credentialId, forKey: credentialIdKey)
            return true
        } catch {
            return false
        }
    }

    /// Face ID releases the secret; the server checks it, rotates it and returns a session token.
    func signIn() async throws -> String {
        guard let id = credentialId else { throw FaceIDSignInError.notEnrolled }
        guard let secret = await readSecret(reason: "Sign in to Boreal Dialer") else { throw FaceIDSignInError.cancelled }
        let body = try JSONSerialization.data(withJSONObject: ["credentialId": id, "secret": secret])
        let data: Data
        do {
            data = try await APIClient.shared.performUnauthenticated(path: "/auth/device-sign-in", method: "POST", body: body)
        } catch APIError.unauthorized {
            clear()
            throw FaceIDSignInError.rejected
        }
        let response = try JSONDecoder().decode(SignInResponse.self, from: data)
        guard response.status.lowercased() == "ok", storeSecret(response.data.secret) else {
            throw FaceIDSignInError.rejected
        }
        return response.data.token
    }

    /// On sign-out: turn Face ID sign-in off on the server, then forget it here.
    func revokeAndClear() async {
        if let id = credentialId, TokenStorage.shared.getToken() != nil,
           let body = try? JSONSerialization.data(withJSONObject: ["credentialId": id]),
           let request = try? APIClient.shared.makeRequest(path: "/auth/device-sign-in/revoke", method: "POST", body: body) {
            _ = try? await APIClient.shared.makeAuthorizedRequest(request)
        }
        clear()
    }
}
