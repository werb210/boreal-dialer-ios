import Foundation

enum APIError: Error {
    case invalidResponse
    case unauthorized
    case notAuthenticated
}

final class APIClient {

    static let shared = APIClient()

    private let session = URLSession.shared

    private init() {}

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

    func authorizedRequest(_ urlRequest: URLRequest) -> URLRequest {
        var request = urlRequest
        let token = TokenStorage.shared.getTokenOrFail()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        print("[AUTH HEADER ATTACHED]", token.prefix(12))
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return authorizedRequest(request)
    }

    func makeAuthorizedRequest(_ request: URLRequest) async throws -> Data {
        let (data, _) = try await makeAuthorizedDataRequest(request)
        return data
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

        if !includeAuthToken {
            print("[REQUEST]", request.httpMethod ?? "", request.url?.absoluteString ?? "")
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                print("[RESPONSE STATUS]", http.statusCode)
            }
            return (data, response)
        }

        return try await perform(request: request)
    }

    func perform(request: URLRequest) async throws -> (Data, URLResponse) {
        print("[REQUEST]", request.httpMethod ?? "", request.url?.absoluteString ?? "")

        if requiresAuthorization(request: request) {
            guard TokenStorage.shared.getToken() != nil else {
                throw APIError.notAuthenticated
            }
            return try await makeAuthorizedDataRequest(request)
        }

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                print("[RESPONSE STATUS]", http.statusCode)
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

    private func makeAuthorizedDataRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let req = authorizedRequest(request)
        print("[REQUEST]", req.httpMethod ?? "", req.url?.absoluteString ?? "")

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("[RESPONSE STATUS]", http.statusCode)

        if http.statusCode == 401 {
            print("[401 ERROR] TOKEN NOT ACCEPTED")
            TokenStorage.shared.clear()
            throw APIError.unauthorized
        }

        return (data, response)
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
