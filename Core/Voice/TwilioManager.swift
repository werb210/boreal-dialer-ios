import Foundation

final class TwilioManager {
    static let shared = TwilioManager()

    // Placeholder for Twilio access token.
    var accessToken: String?

    private init() {}

    func setMockToken(_ token: String) {
        accessToken = token
    }

    func makeCall(to number: String) {
        // Twilio Voice SDK integration goes here.
        _ = number
    }
}
