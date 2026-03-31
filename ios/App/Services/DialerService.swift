import Foundation

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
        guard !authToken.isEmpty else {
            throw APIClientError.httpError(statusCode: 401, body: "Missing auth token")
        }

        let data = try await APIClient.request(
            path: "dialer/token",
            method: "GET",
            token: authToken
        )

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = json["token"] as? String,
            !token.isEmpty
        else {
            throw APIClientError.invalidResponse
        }

        accessToken = token
        identity = json["identity"] as? String
        return token
    }

    func startCall(to: String, authToken: String) async throws -> String {
        guard !authToken.isEmpty else {
            throw APIClientError.httpError(statusCode: 401, body: "Missing auth token")
        }

        let requestBody: [String: Any] = [
            "to": to
        ]

        let data = try await APIClient.request(
            path: "call/start",
            method: "POST",
            body: requestBody,
            token: authToken
        )

        let decoded = try JSONDecoder().decode(StartCallResponse.self, from: data)
        return decoded.call.id
    }

    func sendCallStatus(status: String, callId: String, authToken: String) async throws {
        guard !authToken.isEmpty else {
            throw APIClientError.httpError(statusCode: 401, body: "Missing auth token")
        }

        let normalizedStatus = status.lowercased()
        let alignedStatus: String
        switch normalizedStatus {
        case "initiated":
            alignedStatus = "initiated"
        case "ringing":
            alignedStatus = "ringing"
        case "in-progress", "inprogress", "connected":
            alignedStatus = "in-progress"
        case "completed":
            alignedStatus = "completed"
        default:
            alignedStatus = "failed"
        }

        _ = try await APIClient.request(
            path: "voice/status",
            method: "POST",
            body: ["id": callId, "status": alignedStatus],
            token: authToken
        )
    }
}
