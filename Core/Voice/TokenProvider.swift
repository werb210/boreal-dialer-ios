import Foundation

protocol TokenProvider {
    func fetchAccessToken(forLine lineId: String) async throws -> String
}

final class BFTokenProvider: TokenProvider {

    func fetchAccessToken(forLine lineId: String) async throws -> String {

        let baseURL = await MainActor.run { LineManager.shared.activeLine.baseURL }
        let url = baseURL.appendingPathComponent("api/voice/token")

        var request = URLRequest(url: url)
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
