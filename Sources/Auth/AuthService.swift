import Combine
import Foundation

final class AuthService: ObservableObject {

    static let shared = AuthService()

    @Published var isAuthenticated = false
    @Published var accessTokenExpiry: Date?

    private var refreshTask: Task<Void, Never>?

    private init() {
        if let accessToken = KeychainService.shared.load("accessToken") {
            isAuthenticated = true
            accessTokenExpiry = decodeExpiry(from: accessToken)
            scheduleRefresh()
        }
    }

    private func decodeExpiry(from token: String) -> Date? {
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
              let exp = json["exp"] as? TimeInterval else {
            return nil
        }

        return Date(timeIntervalSince1970: exp)
    }

    func startOTP(phone: String) async throws -> Bool {
        try await OTPService.shared.startOTP(phone: phone)
    }

    func login(phone: String, otp: String) async throws {

        let tokens = try await OTPService.shared.verifyOTP(phone: phone, code: otp)
        let accessToken = tokens.accessToken

        await MainActor.run {
            self.accessTokenExpiry = self.decodeExpiry(from: accessToken)
            self.isAuthenticated = true
            self.scheduleRefresh()
        }

        if shouldInitializeVoice(from: accessToken) {
            PushManager.shared.register()
            Task {
                await VoiceManager.shared.initialize()
            }
        }
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

    func getValidAccessToken() async throws -> String {

        if let token = KeychainService.shared.load("accessToken") {
            return token
        }

        return try await refreshToken()
    }

    func refreshToken() async throws -> String {

        do {
            guard let currentRefreshToken = KeychainService.shared.load("refreshToken") else {
                throw URLError(.userAuthenticationRequired)
            }

            let silo = await MainActor.run { VoiceEngine.shared.silo.rawValue }
            let body = try JSONEncoder().encode([
                "refreshToken": currentRefreshToken
            ])

            let request = try APIClient.shared.makeRequest(
                path: "/api/auth/refresh",
                method: "POST",
                body: body,
                includeAuthToken: false,
                headers: ["X-Silo": silo]
            )

            let (data, response) = try await APIClient.shared.perform(request: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw URLError(.userAuthenticationRequired)
            }

            let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)

            KeychainService.shared.save(decoded.accessToken, for: "accessToken")
            KeychainService.shared.save(decoded.refreshToken, for: "refreshToken")

            await MainActor.run {
                self.accessTokenExpiry = self.decodeExpiry(from: decoded.accessToken)
                self.scheduleRefresh()
            }

            await MainActor.run {
                PushManager.shared.registerDeviceTokenWithTwilio()
            }

            return decoded.accessToken
        } catch {
            await MainActor.run {
                self.logout()
            }
            throw error
        }
    }

    func refreshTokenIfNeededOnResume() async {
        guard let expiry = await MainActor.run(body: { self.accessTokenExpiry }) else {
            return
        }

        guard expiry < Date() else { return }

        do {
            _ = try await refreshToken()
        } catch {
            await MainActor.run {
                self.logout()
            }
        }
    }

    @MainActor
    func scheduleRefresh() {
        refreshTask?.cancel()

        guard let expiry = accessTokenExpiry else { return }

        let refreshTime = expiry.addingTimeInterval(-60)
        let delay = refreshTime.timeIntervalSinceNow

        guard delay > 0 else {
            refreshTask = Task {
                do {
                    _ = try await self.refreshToken()
                } catch {
                    await MainActor.run {
                        self.logout()
                    }
                }
            }
            return
        }

        refreshTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            do {
                _ = try await self.refreshToken()
            } catch {
                await MainActor.run {
                    self.logout()
                }
            }
        }
    }


    func performAuthorizedRequest(_ request: URLRequest) async throws -> Data {

        var authorizedRequest = request
        let accessToken = try await getValidAccessToken()
        authorizedRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await APIClient.shared.perform(request: authorizedRequest)

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 {

            let refreshedToken = try await refreshToken()

            authorizedRequest.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")

            let (retryData, retryResponse) = try await APIClient.shared.perform(request: authorizedRequest)

            if let retryHTTP = retryResponse as? HTTPURLResponse,
               retryHTTP.statusCode == 401 {
                throw URLError(.userAuthenticationRequired)
            }

            return retryData
        }

        return data
    }

    func logout() {
        refreshTask?.cancel()
        KeychainService.shared.delete("accessToken")
        KeychainService.shared.delete("refreshToken")
        accessTokenExpiry = nil
        isAuthenticated = false
    }
}
