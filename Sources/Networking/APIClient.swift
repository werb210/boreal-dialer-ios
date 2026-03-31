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
        return try await execute(req)
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
            TokenStorage.shared.clear()
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
