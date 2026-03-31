import Foundation

final class APIClient {

    static let shared = APIClient()

    private let session = URLSession.shared

    private init() {}

    private var token: String? {
        KeychainService.shared.load("accessToken")
            ?? TokenStorage.shared.getToken()
    }

    func url(path: String) throws -> URL {
        guard let resolvedURL = URL(string: APIConfig.baseURL + normalized(path: path)) else {
            throw URLError(.badURL)
        }

        return resolvedURL
    }

    func makeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        includeAuthToken: Bool = true,
        headers: [String: String] = [:]
    ) throws -> URLRequest {
        if includeAuthToken {
            return authorizedRequest(
                endpoint: normalized(path: path),
                method: method,
                body: body,
                headers: headers
            )
        }

        let url = try url(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    func authorizedRequest(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) -> URLRequest {

        let url = URL(string: "\(APIConfig.BASE_URL)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        guard let token else {
            fatalError("NO TOKEN — AUTH FLOW BROKEN")
        }

        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }

    func perform(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        includeAuthToken: Bool = true,
        headers: [String: String] = [:]
    ) async throws -> (Data, URLResponse) {
        let request = try makeRequest(
            path: path,
            method: method,
            body: body,
            includeAuthToken: includeAuthToken,
            headers: headers
        )

        return try await perform(request: request)
    }

    func perform(request: URLRequest) async throws -> (Data, URLResponse) {
        if requiresAuthorization(request: request) {
            assert(
                request.value(forHTTPHeaderField: "Authorization") != nil,
                "AUTH HEADER MISSING"
            )
        }

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                print("[STATUS]", http.statusCode)
                if http.statusCode == 401 {
                    print("[AUTH FAILED]")
                }
            }
            return (data, response)
        } catch {
            print("[NETWORK ERROR]", error)
            throw error
        }
    }

    func request(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        includeAuthToken: Bool = true,
        headers: [String: String] = [:]
    ) async throws -> (Data, URLResponse) {
        try await perform(
            path: path,
            method: method,
            body: body,
            includeAuthToken: includeAuthToken,
            headers: headers
        )
    }

    private func normalized(path: String) -> String {
        path.hasPrefix("/") ? path : "/\(path)"
    }

    private func requiresAuthorization(request: URLRequest) -> Bool {
        guard let path = request.url?.path else { return false }
        if !path.hasPrefix("/api") {
            return false
        }

        let unauthenticatedPaths = [
            "/api/auth/otp/start",
            "/api/auth/otp/verify",
            "/api/auth/refresh"
        ]

        return !unauthenticatedPaths.contains(path)
    }
}
