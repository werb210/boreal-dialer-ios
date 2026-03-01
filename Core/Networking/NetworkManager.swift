import Foundation

final class NetworkManager {
    static let shared = NetworkManager()

    private init() {}

    func url(for path: String) async -> URL {
        let baseURL = await MainActor.run { LineManager.shared.activeLine.baseURL }
        return baseURL.appendingPathComponent(path)
    }

    func fetchActiveCalls() async throws -> [RemoteCallStatus] {
        let url = await url(for: "api/voice/calls/active")
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
