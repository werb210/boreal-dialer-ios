import Foundation

enum API {

    static func getTwilioToken(line: VoiceEngine.Line) async throws -> String {
        let requestURL = try APIClient.shared.url(path: "/voice/token")

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
        do {
            let requestURL = try APIClient.shared.url(path: "/voice/device-token")

            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(await currentSiloHeader(), forHTTPHeaderField: "X-Silo")

            let body = [
                "deviceToken": token,
                "platform": "ios"
            ]

            request.httpBody = try JSONEncoder().encode(body)
            _ = try await AuthService.shared.performAuthorizedRequest(request)
        } catch {
#if DEBUG
            print("Failed to register VoIP token:", error)
#endif
        }
    }


    static func answerCall(uuid: String) async throws {
        try await updateCallState(path: "/voice/calls/answer", id: uuid)
    }

    static func endCall(uuid: String) async throws {
        try await updateCallState(path: "/voice/calls/end", id: uuid)
    }

    static func sendSMS(_ payload: SendSMSPayload) async throws {
        let requestURL = try APIClient.shared.url(path: "/sms/send")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(await currentSiloHeader(), forHTTPHeaderField: "X-Silo")

        request.httpBody = try JSONEncoder().encode(payload)
        _ = try await AuthService.shared.performAuthorizedRequest(request)
    }


    static func startRecording(callSid: String) async throws {
        try await recordingAction(path: "/voice/record/start", callSid: callSid)
    }

    static func stopRecording(callSid: String) async throws {
        try await recordingAction(path: "/voice/record/stop", callSid: callSid)
    }

    static func getActiveCalls() async throws -> [RemoteCallStatus] {
        try await NetworkManager.shared.fetchActiveCalls()
    }

    static func logCall(duration: Int, status: String) async throws {
        let requestURL = try APIClient.shared.url(path: "/voice/calls/log")

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
        let requestURL = try APIClient.shared.url(path: path)

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
        let requestURL = try APIClient.shared.url(path: path)

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
