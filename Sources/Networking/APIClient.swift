import Foundation

enum APIError: Error {
    case invalidResponse
    case unauthorized
    case notAuthenticated
    case serverError
    case invalidToken
    // BOREAL_DIALER_v829_RELIABILITY - an HTTP error that keeps the server's reason. Every 4xx/5xx used to become a bare
    // .serverError, so staff saw "The operation couldn't be completed. (BorealDialer.APIError error 3.)" and the
    // server's own explanation (e.g. call_not_found) was thrown away.
    case http(status: Int, code: String?, message: String?)
}

// BOREAL_DIALER_v829_RELIABILITY - readable messages wherever an error is shown (error.localizedDescription).
extension APIError: LocalizedError {
    /// Codes BF-Server returns, in words staff understand.
    static let knownCodes: [String: String] = [
        "call_not_found": "This call isn't linked to you yet, so the outcome wasn't saved.",
        "invalid_call_id": "This call has no reference the server recognises.",
        "unknown_disposition": "That call outcome isn't recognised.",
        "invalid_to": "That phone number isn't valid.",
        "caller_id_unconfigured": "No outgoing caller ID is set up for your line. Ask an admin.",
        "call_setup_failed": "The call couldn't be set up. Try again.",
        "forbidden": "You don't have access to that.",
        "not_found": "That item no longer exists.",
        // BOREAL_DIALER_v831_DIALER_POLISH
        "not_staff": "This number isn't set up as a Boreal staff account. Ask an admin to add it.",
        "request_in_progress": "That change is already being saved.",
    ]

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Your session has expired. Sign in again."
        case .notAuthenticated:
            return "You're signed out. Sign in again."
        case .invalidToken:
            return "Sign-in failed. Try again."
        case .invalidResponse, .serverError:
            return "The server didn't respond properly. Try again."
        case .http(let status, let code, let message):
            if let code, let known = APIError.knownCodes[code] { return known }
            if let message, APIError.isReadable(message) { return message }
            if status >= 500 { return "The server had a problem (\(status)). Try again in a moment." }
            if let code, !code.isEmpty { return "The server refused that (\(code))." }
            return "The server refused that (\(status))."
        }
    }

    /// A sentence written for people, not a stack trace or SQL error.
    static func isReadable(_ message: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8, trimmed.count <= 200, trimmed.contains(" ") else { return false }
        let technical = ["relation ", "column ", "syntax", "violates", "undefined", "null value", "ECONN", "Error:", "at /", "stack"]
        return !technical.contains(where: { trimmed.localizedCaseInsensitiveContains($0) })
    }

    /// `{error: "code", message}` or `{error: {code, message}}` or `{message}` from a BF-Server error body.
    static func serverReason(from data: Data) -> (code: String?, message: String?) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (nil, nil) }
        var code: String?
        var message = object["message"] as? String
        if let error = object["error"] as? String {
            code = error
        } else if let error = object["error"] as? [String: Any] {
            code = error["code"] as? String
            message = message ?? (error["message"] as? String)
        } else if let c = object["code"] as? String {
            code = c
        }
        return (code, message)
    }
}

final class APIClient {

    static let shared = APIClient()
    /// BOREAL_DIALER_v831_DIALER_POLISH
    static let requestTimeout: TimeInterval = 20

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
        // BOREAL_DIALER_v831_DIALER_POLISH - 60 s (the default) of silence on a weak signal before a request gave up;
        // the screen just spun. This is the wait between bytes, so long uploads still work.
        request.timeoutInterval = APIClient.requestTimeout
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

        // BOREAL_DIALER_LOG_PRIVACY_v789 - request URLs carry contact ids, phone
        // numbers and search text in their query strings. Logged in DEBUG only,
        // and never with the query string.
#if DEBUG
        print("[REQ]", request.httpMethod ?? "", Self.loggableURL(request.url))
        print("[STATUS]", http.statusCode)
#endif

        if http.statusCode == 401 {
#if DEBUG
            print("[AUTH FAIL] TOKEN REJECTED")
#endif
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
            // BOREAL_DIALER_SESSION_GUARD_v314 - one refused request is not proof the
            // session is gone; SessionGuard asks BF-Server before signing out.
            let refusedURL = request.url
            Task { await SessionGuard.shared.confirm(after: refusedURL) }
            throw APIError.unauthorized
        }

        if http.statusCode >= 400 {
            // BOREAL_DIALER_v829_RELIABILITY - keep the server's reason.
            let reason = APIError.serverReason(from: data)
            throw APIError.http(status: http.statusCode, code: reason.code, message: reason.message)
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

    /// scheme://host/path with no query string or fragment.
    static func loggableURL(_ url: URL?) -> String {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "" }
        components.query = nil
        components.fragment = nil
        return components.string ?? ""
    }

    private func normalized(path: String) -> String {
        path.hasPrefix("/") ? path : "/\(path)"
    }
}
