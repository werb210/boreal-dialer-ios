import Foundation

struct OTPTokens {
    let accessToken: String
    let refreshToken: String?
}

final class OTPService {

    static let shared = OTPService()

    private init() {}

    func startOTP(phone: String) async -> Bool {
        let body = try? JSONSerialization.data(withJSONObject: ["phone": phone])

        guard let body else { return false }

        do {
            let (_, response) = try await APIClient.shared.perform(
                path: "/api/auth/otp/start",
                method: "POST",
                body: body,
                includeAuthToken: false
            )

            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            return (200...299).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    func verifyOTP(phone: String, code: String) async -> OTPTokens? {
        let body = try? JSONSerialization.data(withJSONObject: [
            "phone": phone,
            "code": code
        ])

        guard let body else { return nil }

        do {
            let (data, response) = try await APIClient.shared.perform(
                path: "/api/auth/otp/verify",
                method: "POST",
                body: body,
                includeAuthToken: false
            )

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            let accessToken = (json["accessToken"] as? String) ?? (json["token"] as? String)
            let refreshToken = json["refreshToken"] as? String

            guard let accessToken else {
                return nil
            }

            KeychainService.shared.save(accessToken, for: "accessToken")
            UserDefaults.standard.set(accessToken, forKey: "auth_token")

            if let refreshToken {
                KeychainService.shared.save(refreshToken, for: "refreshToken")
            }

            return OTPTokens(accessToken: accessToken, refreshToken: refreshToken)
        } catch {
            return nil
        }
    }
}
