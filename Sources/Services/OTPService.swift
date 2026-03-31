import Foundation

struct OTPTokens {
    let accessToken: String
    let refreshToken: String?
}

final class OTPService {

    static let shared = OTPService()

    private init() {}

    func startOTP(phone: String) async throws -> Bool {
        let body = try JSONSerialization.data(withJSONObject: ["phone": phone])

        let (_, response) = try await APIClient.shared.perform(
            path: "/api/auth/otp/start",
            method: "POST",
            body: body,
            includeAuthToken: false
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        return (200...299).contains(httpResponse.statusCode)
    }

    func verifyOTP(phone: String, code: String) async throws -> OTPTokens {
        let body = try JSONSerialization.data(withJSONObject: [
            "phone": phone,
            "code": code
        ])

        let (data, response) = try await APIClient.shared.perform(
            path: "/api/auth/otp/verify",
            method: "POST",
            body: body,
            includeAuthToken: false
        )

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)
        guard !decoded.token.isEmpty else {
            fatalError("TOKEN MISSING — SERVER CONTRACT INVALID")
        }

        KeychainService.shared.save(decoded.token, for: "accessToken")
        TokenStorage.shared.save(token: decoded.token)
        print("[TOKEN SAVED]", decoded.token.prefix(12))

        if let refreshToken = decoded.refreshToken {
            KeychainService.shared.save(refreshToken, for: "refreshToken")
        }

        return OTPTokens(accessToken: decoded.token, refreshToken: decoded.refreshToken)
    }
}
