import Foundation

enum API {

    static func getTwilioToken(line: VoiceEngine.Line) async throws -> String {
        let baseURL = await MainActor.run { LineManager.shared.activeLine.baseURL }
        let url = baseURL.appendingPathComponent("api/voice/token")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["lineId": line.backendLineId]
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await AuthService.shared.performAuthorizedRequest(request)

        struct Response: Decodable {
            let token: String
        }

        return try JSONDecoder().decode(Response.self, from: data).token
    }

    static func registerVoIPToken(_ token: String) async {
        let baseURL = await MainActor.run { LineManager.shared.activeLine.baseURL }
        let url = baseURL.appendingPathComponent("api/voice/device-token")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let accessToken = try? await AuthService.shared.getValidAccessToken() else {
            return
        }

        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let body = [
            "deviceToken": token,
            "platform": "ios"
        ]

        request.httpBody = try? JSONEncoder().encode(body)
        _ = try? await URLSession.shared.data(for: request)
    }

    static func answerCall(uuid: String) async throws {
        try await updateCallState(path: "api/voice/calls/answer", id: uuid)
    }

    static func endCall(uuid: String) async throws {
        try await updateCallState(path: "api/voice/calls/end", id: uuid)
    }

    static func sendSMS(_ payload: SendSMSPayload) async throws {
        let baseURL = await MainActor.run { LineManager.shared.activeLine.baseURL }
        let url = baseURL.appendingPathComponent("api/sms/send")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try JSONEncoder().encode(payload)
        _ = try await AuthService.shared.performAuthorizedRequest(request)
    }

    static func getActiveCalls() async throws -> [RemoteCallStatus] {
        try await NetworkManager.shared.fetchActiveCalls()
    }

    static func logCall(duration: Int, status: String) async throws {
        let baseURL = await MainActor.run { LineManager.shared.activeLine.baseURL }
        let url = baseURL.appendingPathComponent("api/voice/calls/log")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = CallLogPayload(duration: duration, status: status)
        request.httpBody = try JSONEncoder().encode(payload)

        _ = try await AuthService.shared.performAuthorizedRequest(request)
    }

    static func reconcileActiveCalls() async throws {
        let serverCalls = try await getActiveCalls()
        await MainActor.run {
            VoiceEngine.shared.syncWithServer(serverCalls)
        }
    }

    static func executeQueuedAction(_ action: QueuedAction) async throws {

        switch action.type {
        case "send_sms":
            let message = try JSONDecoder().decode(SendSMSPayload.self, from: action.payload)
            try await sendSMS(message)

        case "end_call":
            let data = try JSONDecoder().decode(EndCallPayload.self, from: action.payload)
            try await endCall(uuid: data.uuid)

        default:
            break
        }
    }

    private static func updateCallState(path: String, id: String) async throws {
        let baseURL = await MainActor.run { LineManager.shared.activeLine.baseURL }
        let url = baseURL.appendingPathComponent(path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try JSONEncoder().encode(["id": id])

        _ = try await AuthService.shared.performAuthorizedRequest(request)
    }
}

private struct CallLogPayload: Codable {
    let duration: Int
    let status: String
}
