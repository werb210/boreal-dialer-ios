import Foundation

protocol TokenProvider {
    func fetchAccessToken(forLine lineId: String) async throws -> String
}

final class BFTokenProvider: TokenProvider {

    func fetchAccessToken(forLine lineId: String) async throws -> String {

        let requestURL = try APIClient.shared.url(path: "/api/voice/token")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"

        let body = ["lineId": lineId]
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await AuthService.shared.performAuthorizedRequest(request)

        struct Response: Decodable {
            let token: String
        }

        return try JSONDecoder().decode(Response.self, from: data).token
    }
}
