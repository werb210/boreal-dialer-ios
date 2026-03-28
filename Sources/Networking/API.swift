import Foundation

enum API {

    static func getTwilioToken(line: VoiceEngine.Line) async throws -> String {
        guard let requestURL = APIClient.shared.url(path: "/api/voice/token") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(await currentSiloHeader(), forHTTPHeaderField: "X-Silo")

        let body = ["lineId": line.backendLineId]
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await AuthService.shared.performAuthorizedRequest(request)

        struct Response: Decodable {
            let token: String
        }

        return try JSONDecoder().decode(Response.self, from: data).token
    }

    static func registerVoIPToken(_ token: String) async {
        guard let requestURL = APIClient.shared.url(path: "/api/voice/device-token") else {
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(await currentSiloHeader(), forHTTPHeaderField: "X-Silo")

        guard let accessToken = try? await AuthService.shared.getValidAccessToken() else {
            return
        }

        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let body = [
            "deviceToken": token,
            "platform": "ios"
        ]

        request.httpBody = try? JSONEncoder().encode(body)
        _ = try? await AuthService.shared.performAuthorizedRequest(request)
    }

    static func answerCall(uuid: String) async throws {
        try await updateCallState(path: "api/voice/calls/answer", id: uuid)
    }

    static func endCall(uuid: String) async throws {
        try await updateCallState(path: "api/voice/calls/end", id: uuid)
    }

    static func sendSMS(_ payload: SendSMSPayload) async throws {
        guard let requestURL = APIClient.shared.url(path: "/api/sms/send") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(await currentSiloHeader(), forHTTPHeaderField: "X-Silo")

        request.httpBody = try JSONEncoder().encode(payload)
        _ = try await AuthService.shared.performAuthorizedRequest(request)
    }


    static func startRecording(callSid: String) async throws {
        try await recordingAction(path: "api/voice/record/start", callSid: callSid)
    }

    static func stopRecording(callSid: String) async throws {
        try await recordingAction(path: "api/voice/record/stop", callSid: callSid)
    }

    static func getActiveCalls() async throws -> [RemoteCallStatus] {
        try await NetworkManager.shared.fetchActiveCalls()
    }

    static func logCall(duration: Int, status: String) async throws {
        guard let requestURL = APIClient.shared.url(path: "/api/voice/calls/log") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(await currentSiloHeader(), forHTTPHeaderField: "X-Silo")

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


    private static func recordingAction(path: String, callSid: String) async throws {
        guard let requestURL = APIClient.shared.url(path: path) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(await currentSiloHeader(), forHTTPHeaderField: "X-Silo")

        request.httpBody = try JSONEncoder().encode(["callSid": callSid])
        _ = try await AuthService.shared.performAuthorizedRequest(request)
    }

    private static func currentSiloHeader() async -> String {
        await MainActor.run { VoiceEngine.shared.silo.rawValue }
    }

    private static func updateCallState(path: String, id: String) async throws {
        guard let requestURL = APIClient.shared.url(path: path) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(await currentSiloHeader(), forHTTPHeaderField: "X-Silo")

        request.httpBody = try JSONEncoder().encode(["id": id])

        _ = try await AuthService.shared.performAuthorizedRequest(request)
    }
}

private struct CallLogPayload: Codable {
    let duration: Int
    let status: String
}
