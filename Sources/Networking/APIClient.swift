import Foundation

class APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: APIConfig.baseURL)!

    func request(path: String) -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = UserDefaults.standard.string(forKey: "auth_token") {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }
}
