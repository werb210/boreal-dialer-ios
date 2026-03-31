import Foundation

struct VoiceTokenResponse: Decodable {
    let token: String
    let identity: String
}

struct StartCallResponse: Decodable {
    struct CallPayload: Decodable {
        let id: String
    }

    let call: CallPayload
}

final class DialerService {
    static let shared = DialerService()

    private(set) var accessToken: String?
    private(set) var identity: String?
    private init() {}

    func fetchToken(authToken: String) async throws -> String {
        let data = try await APIClient.request(
            path: "api/voice/token",
            method: "POST",
            token: authToken
        )

        let decoded = try JSONDecoder().decode(VoiceTokenResponse.self, from: data)
        accessToken = decoded.token
        identity = decoded.identity
        return decoded.token
    }

    func startCall(to: String, authToken: String) async throws -> String {
        let requestBody: [String: Any] = [
            "to": to,
            "applicationId": UUID().uuidString,
        ]

        let data = try await APIClient.request(
            path: "api/voice/calls/start",
            method: "POST",
            body: requestBody,
            token: authToken
        )

        let decoded = try JSONDecoder().decode(StartCallResponse.self, from: data)
        return decoded.call.id
    }

    func sendCallStatus(status: String, callId: String, authToken: String) async throws {
        let normalizedStatus = status.lowercased()
        if ["completed", "failed", "missed"].contains(normalizedStatus) {
            _ = try await APIClient.request(
                path: "api/voice/calls/end",
                method: "POST",
                body: ["id": callId],
                token: authToken
            )
        }
    }
}
