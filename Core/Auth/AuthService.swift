import Combine
import Foundation

final class AuthService: ObservableObject {

    static let shared = AuthService()

    @Published var isAuthenticated = false
    @Published var accessTokenExpiry: Date?

    private var refreshTask: Task<Void, Never>?
    private lazy var secureSession: URLSession = {
        URLSession(configuration: .default, delegate: PinnedSessionDelegate(), delegateQueue: nil)
    }()

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

    private func baseURL() async -> URL {
        await MainActor.run { LineManager.shared.activeLine.baseURL }
    }

    func login(phone: String, otp: String) async throws {

        let url = await baseURL().appendingPathComponent("api/auth/otp/verify")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let silo = await MainActor.run { VoiceEngine.shared.silo.rawValue }
        request.setValue(silo, forHTTPHeaderField: "X-Silo")

        let body = ["phone": phone, "code": otp]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await secureSession.data(for: request)

        let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)

        KeychainService.shared.save(decoded.accessToken, for: "accessToken")
        KeychainService.shared.save(decoded.refreshToken, for: "refreshToken")

        await MainActor.run {
            self.accessTokenExpiry = self.decodeExpiry(from: decoded.accessToken)
            self.isAuthenticated = true
            self.scheduleRefresh()
            WebSocketManager.shared.connect(
                line: LineManager.shared.activeLine,
                accessToken: decoded.accessToken
            )
        }
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

            let url = await baseURL().appendingPathComponent("api/auth/refresh")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let silo = await MainActor.run { VoiceEngine.shared.silo.rawValue }
        request.setValue(silo, forHTTPHeaderField: "X-Silo")

            request.httpBody = try JSONEncoder().encode([
                "refreshToken": currentRefreshToken
            ])

            let (data, response) = try await secureSession.data(for: request)

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
                WebSocketManager.shared.connect(
                    line: LineManager.shared.activeLine,
                    accessToken: decoded.accessToken
                )
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
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

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

        let (data, response) = try await secureSession.data(for: authorizedRequest)

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 {

            let refreshedToken = try await refreshToken()

            authorizedRequest.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")

            let (retryData, retryResponse) = try await secureSession.data(for: authorizedRequest)

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
        WebSocketManager.shared.disconnect()
        KeychainService.shared.delete("accessToken")
        KeychainService.shared.delete("refreshToken")
        accessTokenExpiry = nil
        isAuthenticated = false
    }
}
