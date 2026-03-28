import Foundation

final class NetworkManager {
    static let shared = NetworkManager()

    private init() {}

    func url(for path: String) async throws -> URL {
        guard let requestURL = APIClient.shared.url(path: path) else {
            throw URLError(.badURL)
        }

        return requestURL
    }

    func fetchActiveCalls() async throws -> [RemoteCallStatus] {
        let url = try await url(for: "api/voice/calls/active")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let silo = await MainActor.run { VoiceEngine.shared.silo.rawValue }
        request.setValue(silo, forHTTPHeaderField: "X-Silo")

        let data = try await AuthService.shared.performAuthorizedRequest(request)
        return try JSONDecoder().decode([RemoteCallStatus].self, from: data)
    }
}

struct RemoteCallStatus: Codable {
    let id: String
    let number: String
    let status: String
}
