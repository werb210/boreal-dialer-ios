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
            "code": code,
            // BOREAL_DIALER_v831_DIALER_POLISH - BF-Server v831 answers 403 not_staff for a number that isn't staff,
            // instead of a client sign-in that looked normal and never rang.
            "userType": "staff"
        ])

        return try await APIClient.shared.performUnauthenticated(
            path: "/auth/otp/verify",
            method: "POST",
            body: body
        )
    }
}
