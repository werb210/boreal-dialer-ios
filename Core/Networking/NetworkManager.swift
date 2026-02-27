import Foundation

final class NetworkManager {
    static let shared = NetworkManager()

    private init() {}

    func fetchMockToken() -> String {
        // Return a mock Twilio token placeholder.
        "MOCK_TWILIO_TOKEN"
    }
}
