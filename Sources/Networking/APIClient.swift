import Foundation

final class APIClient {

    static let shared = APIClient()

    private let session = URLSession.shared

    private init() {}

    private var token: String? {
        KeychainService.shared.load("accessToken")
            ?? UserDefaults.standard.string(forKey: "auth_token")
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
        let url = try url(path: path)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if includeAuthToken, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
        try await session.data(for: request)
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
}
