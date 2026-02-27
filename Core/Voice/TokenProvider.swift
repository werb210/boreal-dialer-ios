import Foundation

protocol TokenProvider {
    func fetchAccessToken() async throws -> String
}

final class BFTokenProvider: TokenProvider {

    func fetchAccessToken() async throws -> String {

        let url = URL(string: "https://YOUR-BF-SERVER/api/voice/token")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)

        struct Response: Decodable {
            let token: String
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)

        return decoded.token
    }
}
