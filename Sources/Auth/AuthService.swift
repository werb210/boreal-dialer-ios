import Combine
import Foundation

final class AuthService: ObservableObject {

    static let shared = AuthService()

    @Published var isAuthenticated = false

    private init() {
        if TokenStorage.shared.getToken() != nil {
            isAuthenticated = true
        }
    }

    func startOTP(phone: String) async throws -> Bool {
        try await OTPService.shared.startOTP(phone: phone)
    }

    func login(phone: String, otp: String) async throws {
        let data = try await OTPService.shared.verifyOTP(phone: phone, code: otp)
        let token = try handleAuthResponse(data)

        await MainActor.run {
            self.isAuthenticated = true
        }

        if shouldInitializeVoice(from: token) {
            PushManager.shared.register()
            Task {
                await VoiceManager.shared.initialize()
            }
        }
    }

    @discardableResult
    func handleAuthResponse(_ data: Data) throws -> String {
        let response = try JSONDecoder().decode(AuthResponse.self, from: data)

        guard response.status.lowercased() == "ok" else {
            throw APIError.invalidResponse
        }

        let token = response.data.token

        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw APIError.invalidToken
        }

        TokenStorage.shared.save(token: token)

        // After saving the auth token, register the push token with BF-Server.
        if let pushToken = PushManager.shared.deviceTokenString {
            Task {
                do {
                    let body = try JSONSerialization.data(withJSONObject: [
                        "token": pushToken,
                        "platform": "ios"
                    ])
                    let request = try APIClient.shared.authorizedRequest(
                        endpoint: "/auth/device-token",
                        method: "POST",
                        body: body
                    )
                    _ = try await APIClient.shared.execute(request)
                    print("[PUSH] Device token registered with BF-Server")
                } catch {
                    print("[PUSH] Failed to register device token:", error)
                }
            }
        }

        print("[TOKEN SAVED]", token.prefix(12))
        return token
    }

    private func shouldInitializeVoice(from token: String) -> Bool {
        guard let role = decodeClaim("role", from: token) else {
            return false
        }

        let normalized = role.lowercased()
        return normalized == "admin" || normalized == "staff"
    }

    private func decodeClaim(_ key: String, from token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count > 1 else { return nil }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json[key] as? String else {
            return nil
        }

        return value
    }


    func performAuthorizedRequest(_ request: URLRequest) async throws -> Data {
        try await APIClient.shared.makeAuthorizedRequest(request)
    }

    func logout() {
        TokenStorage.shared.clear()
        isAuthenticated = false
    }
}
