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
                    endpoint: "/crm/events",
                    method: "POST",
                    body: body
                )
                _ = try await APIClient.shared.execute(request)
            } catch {
                print("[CRM] Failed to log recording consent:", error)
            }
        }
    }

    func startRecording(callSid: String) async throws {
        try await API.startRecording(callSid: callSid)
        isRecording = true
        activeCallSid = callSid
        Telemetry.event("recording_started", metadata: ["callSid": callSid, "consent": consentState])
    }

    func stopRecording(callSid: String) async throws {
        try await API.stopRecording(callSid: callSid)
        isRecording = false
        Telemetry.event("recording_stopped", metadata: ["callSid": callSid])
    }

}
