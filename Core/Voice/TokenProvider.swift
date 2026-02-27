import Foundation

protocol TokenProvider {
    func fetchAccessToken() async throws -> String
}

final class MockTokenProvider: TokenProvider {
    func fetchAccessToken() async throws -> String {
        return "MOCK_TWILIO_ACCESS_TOKEN"
    }
}
