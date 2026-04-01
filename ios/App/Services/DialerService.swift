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
    private var isCalling = false
    private init() {}

    func ensureValidToken(authToken: String) async throws {
        if accessToken == nil {
            _ = try await fetchToken(authToken: authToken)
        }
    }

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
            throw NSError(domain: "invalid_token", code: 0)
        }

        print("[DialerService] token fetched")
        accessToken = token
        identity = json["identity"] as? String
        return token
    }

    func startCall(to: String, authToken: String) async throws -> String {
        guard !authToken.isEmpty else {
            throw APIClientError.httpError(statusCode: 401, body: "Missing auth token")
        }

        if isCalling {
            print("Call blocked: already in progress")
            throw NSError(domain: "call_in_progress", code: 0)
        }
        isCalling = true
        defer { isCalling = false }

        try await ensureValidToken(authToken: authToken)

        let requestBody: [String: Any] = ["to": to]
        let data = try await requestWithAuthRetry(authToken: authToken) {
            try await APIClient.request(
                path: "call/start",
                method: "POST",
                body: requestBody,
                token: authToken
            )
        }
        if data.isEmpty {
            print("Warning: empty call start response")
        }

        let decoded = try JSONDecoder().decode(StartCallResponse.self, from: data)
        print("[DialerService] call started")
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

        do {
            _ = try await requestWithAuthRetry(authToken: authToken) {
                try await APIClient.request(
                    path: "voice/status",
                    method: "POST",
                    body: ["id": callId, "status": alignedStatus],
                    token: authToken
                )
            }
            print("[DialerService] status sent")
        } catch {
            print("Failed to report call status:", error)
        }
    }

    private func requestWithAuthRetry(
        authToken: String,
        request: () async throws -> Data
    ) async throws -> Data {
        do {
            return try await request()
        } catch APIClientError.authExpired {
            accessToken = nil
            _ = try await fetchToken(authToken: authToken)
            return try await request()
        }
    }
}
