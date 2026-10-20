import Foundation

enum API {

    static func getTwilioToken(line: VoiceEngine.Line) async throws -> String {
        let requestURL = try APIClient.shared.url(path: "/voice/token")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(currentSiloHeader(), forHTTPHeaderField: "X-Silo")

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
        request.setValue(currentSiloHeader(), forHTTPHeaderField: "X-Silo")

        request.httpBody = try JSONEncoder().encode(payload)
        _ = try await AuthService.shared.performAuthorizedRequest(request)
    }


    // BOREAL_DIALER_DEAD_VOICE_ROUTES_v15 - /voice/calls/log does not exist.
    // call-events is the endpoint the portal uses; it resolves the contact from
    // the dialled number and writes the activity to that contact's timeline.
    // to_number is required by the server, so a call with no number is skipped
    // rather than posted and rejected.
    // BOREAL_DIALER_v831_DIALER_POLISH - an incoming call put the caller in to_number with no direction, so the
    // timeline showed it as a call Todd placed. It now says inbound and names the caller in from_number (BF-Server
    // v831). `key` is the Idempotency-Key: the same call logged twice (a resend after a lost reply) counts once.
    static func callLogBody(duration: Int, status: String, number: String?, callSid: String?, direction: String) -> Data? {
        guard let number, !number.isEmpty else { return nil }
        let inbound = direction == "inbound"
        var payload: [String: Any] = [
            "event_type": callEventType(status), // BOREAL_DIALER_v817_CALLS
            "direction": inbound ? "inbound" : "outbound",
            "duration_seconds": duration,
            "payload": ["status": status],
        ]
        if inbound { payload["from_number"] = number } else { payload["to_number"] = number }
        if let callSid { payload["twilio_call_sid"] = callSid }
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    static func logCall(duration: Int, status: String, number: String?, callSid: String?,
                        direction: String = "outbound", key: UUID = UUID()) async throws {
        guard let body = callLogBody(duration: duration, status: status, number: number, callSid: callSid, direction: direction) else { return }
        let requestURL = try APIClient.shared.url(path: "/communications/call-events")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = APIClient.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(currentSiloHeader(), forHTTPHeaderField: "X-Silo")
        request.setValue(key.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = body

        _ = try await AuthService.shared.performAuthorizedRequest(request)
    }

    // BOREAL_DIALER_v817_CALLS - BF-Server's call_events only accepts call.started / call.ended /
    // call.failed / call.missed / call.declined. "call_completed" failed its CHECK constraint, so
    // every call log 500'd and no call reached the contact's timeline.
    static func callEventType(_ status: String) -> String {
        switch status.lowercased() {
        case "failed", "error", "busy": return "call.failed"
        case "no-answer", "noanswer", "missed": return "call.missed"
        case "declined", "rejected", "canceled", "cancelled": return "call.declined"
        default: return "call.ended"
        }
    }

    // BOREAL_DIALER_OFFLINE_v303 - the same call-events body logCall sends, saved for later.
    static func queueCallLog(duration: Int, status: String, number: String?, callSid: String?,
                             direction: String = "outbound", key: UUID = UUID()) {
        guard let body = callLogBody(duration: duration, status: status, number: number, callSid: callSid, direction: direction) else { return }
        OfflineQueue.shared.enqueue(label: "Call log", path: "/communications/call-events", body: body, id: key)
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


    // BOREAL_DIALER_v831_DIALER_POLISH - one source for the silo: APIConfig.activeSilo, which LineManager keeps.
    // This read VoiceEngine.silo, which the Focus filter could move on its own, so texts and the calling token could
    // go out under a different silo from everything else (and in lower case).
    private static func currentSiloHeader() -> String {
        APIConfig.siloHeader(for: APIConfig.activeSilo)
    }

}
