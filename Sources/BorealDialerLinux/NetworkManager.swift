import Foundation

final class NetworkManager {
    static let shared = NetworkManager()

    private init() {}

    func fetchMockToken() -> String {
        "MOCK_TWILIO_TOKEN"
    }
}
