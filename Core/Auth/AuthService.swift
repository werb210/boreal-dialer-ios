import Combine
import Foundation

final class AuthService: ObservableObject {

    static let shared = AuthService()

    @Published var isAuthenticated = false

    private init() {
        if KeychainService.shared.load("accessToken") != nil {
            isAuthenticated = true
        }
    }

    private func baseURL() async -> URL {
        await MainActor.run { LineManager.shared.activeLine.baseURL }
    }

    func login(phone: String, otp: String) async throws {

        let url = await baseURL().appendingPathComponent("api/auth/otp/verify")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["phone": phone, "code": otp]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)

        let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)

        KeychainService.shared.save(decoded.accessToken, for: "accessToken")
        KeychainService.shared.save(decoded.refreshToken, for: "refreshToken")

        await MainActor.run {
            self.isAuthenticated = true
        }
    }

    func getValidAccessToken() async throws -> String {

        if let token = KeychainService.shared.load("accessToken") {
            return token
        }

        return try await refresh()
    }

    private func refresh() async throws -> String {

        guard let refreshToken = KeychainService.shared.load("refreshToken") else {
            throw URLError(.userAuthenticationRequired)
        }

        let url = await baseURL().appendingPathComponent("api/auth/refresh")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try JSONEncoder().encode([
            "refreshToken": refreshToken
        ])

        let (data, _) = try await URLSession.shared.data(for: request)

        let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)

        KeychainService.shared.save(decoded.accessToken, for: "accessToken")
        KeychainService.shared.save(decoded.refreshToken, for: "refreshToken")

        return decoded.accessToken
    }

    func logout() {
        KeychainService.shared.delete("accessToken")
        KeychainService.shared.delete("refreshToken")
        isAuthenticated = false
    }
}
