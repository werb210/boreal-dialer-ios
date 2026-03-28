import Foundation

final class APIClient {

    static let shared = APIClient()

    private init() {}

    private var token: String? {
        KeychainService.shared.load("accessToken")
            ?? UserDefaults.standard.string(forKey: "auth_token")
    }

    func url(path: String) -> URL? {
        URL(string: APIConfig.baseURL + normalized(path: path))
    }

    func makeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        includeAuthToken: Bool = true,
        headers: [String: String] = [:]
    ) -> URLRequest? {
        guard let url = url(path: path) else {
            return nil
        }

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

    func request(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        includeAuthToken: Bool = true,
        headers: [String: String] = [:],
        session: URLSession = .shared
    ) async throws -> (Data, URLResponse) {
        guard let request = makeRequest(
            path: path,
            method: method,
            body: body,
            includeAuthToken: includeAuthToken,
            headers: headers
        ) else {
            throw URLError(.badURL)
        }

        return try await session.data(for: request)
    }

    private func normalized(path: String) -> String {
        path.hasPrefix("/") ? path : "/\(path)"
    }
}
