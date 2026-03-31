import Foundation

final class OTPService {

    static let shared = OTPService()

    private init() {}

    func startOTP(phone: String) async throws -> Bool {
        let body = try JSONSerialization.data(withJSONObject: ["phone": phone])

        let data = try await APIClient.shared.performUnauthenticated(
            path: "/auth/otp/start",
            method: "POST",
            body: body
        )

        _ = data
        return true
    }

    func verifyOTP(phone: String, code: String) async throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: [
            "phone": phone,
            "code": code
        ])

        return try await APIClient.shared.performUnauthenticated(
            path: "/auth/otp/verify",
            method: "POST",
            body: body
        )
    }
}
