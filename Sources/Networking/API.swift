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

    static func sendSMS(_ payload: SendSMSPayload) async throws {
        // BOREAL_DIALER_CONTACTS_TAB_v7 - /sms/send is the marketing blast route.
        let requestURL = try APIClient.shared.url(path: "/communications/sms")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(await currentSiloHeader(), forHTTPHeaderField: "X-Silo")

        request.httpBody = try JSONEncoder().encode(payload)
        _ = try await AuthService.shared.performAuthorizedRequest(request)
    }


    // BOREAL_DIALER_DEAD_VOICE_ROUTES_v15 - /voice/calls/log does not exist.
    // call-events is the endpoint the portal uses; it resolves the contact from
    // the dialled number and writes the activity to that contact's timeline.
    // to_number is required by the server, so a call with no number is skipped
    // rather than posted and rejected.
    static func logCall(duration: Int, status: String, number: String?, callSid: String?) async throws {
        guard let number, !number.isEmpty else { return }
        let requestURL = try APIClient.shared.url(path: "/communications/call-events")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(await currentSiloHeader(), forHTTPHeaderField: "X-Silo")

        var payload: [String: Any] = [
            "event_type": "call_completed",
            "to_number": number,
            "duration_seconds": duration,
            "payload": ["status": status],
        ]
        if let callSid { payload["twilio_call_sid"] = callSid }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        _ = try await AuthService.shared.performAuthorizedRequest(request)
    }

    static func executeQueuedAction(_ action: QueuedAction) async throws {

        switch action.type {
        case "send_sms":
            let message = try JSONDecoder().decode(SendSMSPayload.self, from: action.payload)
            try await sendSMS(message)

        default:
            break
        }
    }


    private static func currentSiloHeader() async -> String {
        await MainActor.run { VoiceEngine.shared.silo.rawValue }
    }

}
