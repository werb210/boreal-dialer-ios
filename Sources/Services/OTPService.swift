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

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        let accessToken = (json["accessToken"] as? String) ?? (json["token"] as? String)
        let refreshToken = json["refreshToken"] as? String

        guard let accessToken else {
            throw URLError(.userAuthenticationRequired)
        }

        KeychainService.shared.save(accessToken, for: "accessToken")
        UserDefaults.standard.set(accessToken, forKey: "auth_token")

        if let refreshToken {
            KeychainService.shared.save(refreshToken, for: "refreshToken")
        }

        return OTPTokens(accessToken: accessToken, refreshToken: refreshToken)
    }
}
