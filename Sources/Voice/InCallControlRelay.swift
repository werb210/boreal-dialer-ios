// BOREAL_DIALER_WATCH_INCALL_v1
// Turns a wrist request into the two BF-Server calls that already exist:
//   POST /api/voice/conferences/:id/participants/:pid/mute   { muted }
//   POST /api/voice/calls/:callSid/dtmf                      { digits }
// The handoff brief recorded these as server-blocked; voiceMidCall.ts:34 and
// :97 implement both, permission-checked and complete.
import Foundation

@MainActor
public final class InCallControlRelay {
    public static let shared = InCallControlRelay()
    private init() {}

    // BOREAL_DIALER_WATCH_INCALL_v2
    // v1 declared its own copies of these and nothing ever set them, so mute
    // silently did nothing. ConferenceSession already publishes conferenceId
    // and selfParticipantId and is maintained by the call layer; read from it
    // rather than mirroring state that can drift out of sync with the call.
    weak var session: ConferenceSession?

    /// Only the DTMF path needs a raw Twilio call SID, which the conference
    /// session does not carry. Set by the voice layer when a call connects.
    public var activeCallSid: String?

    public func perform(_ message: WatchInCallMessage) async {
        switch message.control {
        case .mute, .unmute:
            guard let conferenceId = session?.conferenceId,
                  let participantId = session?.selfParticipantId else { return }
            await post(path: "/voice/conferences/\(conferenceId)/participants/\(participantId)/mute",
                       body: ["muted": message.control == .mute])
        case .dtmf:
            guard let callSid = activeCallSid, let digits = message.digits,
                  digits.allSatisfy({ "0123456789*#".contains($0) }) else { return }
            await post(path: "/voice/calls/\(callSid)/dtmf", body: ["digits": digits])
        }
    }

    private func post(path: String, body: [String: Any]) async {
        guard let url = URL(string: APIConfig.BASE_URL + path),
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BF", forHTTPHeaderField: "X-Silo")
        if let token = TokenStorage.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = payload
        // Best-effort: a failed mute must never disturb a live call.
        _ = try? await URLSession.shared.data(for: request)
    }
}
