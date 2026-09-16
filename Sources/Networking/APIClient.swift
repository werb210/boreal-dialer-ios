import Foundation

enum APIError: Error {
    case invalidResponse
    case unauthorized
    case notAuthenticated
    case serverError
    case invalidToken
}

final class APIClient {

    static let shared = APIClient()

    private init() {}

    // BOREAL_DIALER_BI_CONTACTS_v51 - `baseURL` overrides the default host for
    // the handful of reads that live on bi-server rather than BF-Server.
    // Everything else keeps passing nil and lands on APIConfig.baseURL.
    func url(path: String, baseURL: String? = nil) throws -> URL {
        guard let resolvedURL = URL(string: (baseURL ?? APIConfig.baseURL) + normalized(path: path)) else {
            throw URLError(.badURL)
        }

        return resolvedURL
    }

    func makeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:],
        silo: Silo? = nil,
        // BOREAL_DIALER_BI_CONTACTS_v51
        baseURL: String? = nil
    ) throws -> URLRequest {
        let url = try url(path: path, baseURL: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // BOREAL_DIALER_SDK_AND_ISOLATION_v5 - read the silo from APIConfig,
        // which LineManager keeps current. Reaching into LineManager here
        // crossed onto the main actor from a nonisolated request builder.
        // BOREAL_DIALER_CONTACTS_SILO_v39 - `silo` overrides it for the one
        // surface that reads across silos.
        request.setValue(
            APIConfig.siloHeader(for: silo ?? APIConfig.activeSilo),
            forHTTPHeaderField: "X-Silo"
        )

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }

    func authorizedRequest(_ request: URLRequest) -> URLRequest {
        var req = request

        let token = TokenStorage.shared.getTokenOrFail()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return req
    }

    func authorizedRequest(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) throws -> URLRequest {
        let request = try makeRequest(path: endpoint, method: method, body: body, headers: headers)
        return authorizedRequest(request)
    }

    func makeAuthorizedRequest(_ request: URLRequest) async throws -> Data {
        guard TokenStorage.shared.getToken() != nil else {
            throw APIError.notAuthenticated
        }

        let req = authorizedRequest(request)
        // BOREAL_DIALER_OFFLINE_v303 - remember good reads; with no signal, return the last copy.
        do {
            let data = try await execute(req)
            ResponseCache.store(data, for: req)
            return data
        } catch {
            if OfflineQueue.isOffline(error), let cached = ResponseCache.load(for: req) {
                return cached
            }
            throw error
        }
    }

    func execute(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("[REQ]", request.httpMethod ?? "", request.url?.absoluteString ?? "")
        print("[STATUS]", http.statusCode)

        if http.statusCode == 401 {
            print("[AUTH FAIL] TOKEN REJECTED")
            // BOREAL_DIALER_SESSION_EXPIRY_v174
            // Clearing the token was only half the job: nothing anywhere caught
            // APIError.unauthorized, so the app stayed on the tab bar with a
            // wiped token and every screen rendered its own "Could not load"
            // message - quick call, recents, contacts, messages, voicemail,
            // team, all at once - with no indication that the session had
            // simply expired. The Watch then could not link either, because the
            // enrollment code is minted by this same authenticated client.
            // Flipping isAuthenticated returns the app to the login gate that
            // BorealDialerApp already renders.
            TokenStorage.shared.clear()
            Task { await AuthService.shared.invalidateSessionAfterIdentityMismatch() }
            throw APIError.unauthorized
        }

        if http.statusCode >= 400 {
            throw APIError.serverError
        }

        return data
    }

    func executeUnauthenticated(_ request: URLRequest) async throws -> Data {
        try await execute(request)
    }

    func performUnauthenticated(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> Data {
        let request = try makeRequest(path: path, method: method, body: body, headers: headers)
        return try await executeUnauthenticated(request)
    }

    private func normalized(path: String) -> String {
        path.hasPrefix("/") ? path : "/\(path)"
    }
}
