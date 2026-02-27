import Foundation

protocol TokenProvider {
    func fetchAccessToken(forLine lineId: String) async throws -> String
}

final class BFTokenProvider: TokenProvider {

    func fetchAccessToken(forLine lineId: String) async throws -> String {

        let url = URL(string: "https://YOUR-BF-SERVER/api/voice/token")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let body = ["lineId": lineId]
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let accessToken = try await AuthService.shared.getValidAccessToken()

        request.setValue("Bearer \(accessToken)",
                         forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)

        struct Response: Decodable {
            let token: String
        }

        return try JSONDecoder().decode(Response.self, from: data).token
    }
}
