// BOREAL_DIALER_LAST_DEAD_ROUTES_v43 - /crm/events does not exist on
// BF-Server; calendar events are served from /calendar/events.
import Foundation

@MainActor
final class RecordingManager: ObservableObject {

    static let shared = RecordingManager()

    @Published private(set) var isRecording = false
    @Published private(set) var consentState: String = "unknown"

    private var activeContactId: String?
    private var activeCallSid: String?

    private init() {}

    func beginCall(callSid: String, contactId: String?) {
        activeCallSid = callSid
        activeContactId = contactId
        consentState = "unknown"
        isRecording = false
    }

    func setConsentState(_ value: String) {
        consentState = value
        Telemetry.event("recording_consent_updated", metadata: ["state": value])

        guard let contactId = activeContactId, let callSid = activeCallSid else { return }
        let given = value.lowercased() == "given" || value.lowercased() == "true" || value.lowercased() == "yes"

        Task {
            do {
                let body = try JSONSerialization.data(withJSONObject: [
                    "contactId": contactId,
                    "eventType": "recording_consent_given",
                    "payload": [
                        "callSid": callSid,
                        "consent": given
                    ]
                ])
                let request = try APIClient.shared.authorizedRequest(
                    endpoint: "/calendar/events",
                    method: "POST",
                    body: body
                )
                _ = try await APIClient.shared.execute(request)
            } catch {
                print("[CRM] Failed to log recording consent:", error)
            }
        }
    }

    // BOREAL_DIALER_DEAD_VOICE_ROUTES_v15 - recording is a conference operation.
    // ConferenceSession.recording(op:) drives it; this only tracks the flag so
    // the UI can reflect state.
    func setRecording(_ recording: Bool) {
        isRecording = recording
        Telemetry.event(
            recording ? "recording_started" : "recording_stopped",
            metadata: ["consent": consentState]
        )
    }

}
