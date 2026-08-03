import Foundation

final class NetworkManager {
    static let shared = NetworkManager()

    private init() {}

    func url(for path: String) async throws -> URL {
        try APIClient.shared.url(path: path)
    }
}

struct RemoteCallStatus: Codable {
    let id: String
    let number: String
    let status: String
}
