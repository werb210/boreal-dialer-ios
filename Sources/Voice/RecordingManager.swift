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

        // Log to BF-Server CRM timeline
        if let contactId = activeContactId, let callSid = activeCallSid {
            Task {
                await logConsentToCRM(contactId: contactId, callSid: callSid, consentState: value)
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

    private func logConsentToCRM(contactId: String, callSid: String, consentState: String) async {
        guard let url = URL(string: "\(APIConfig.baseURL)/crm/events") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth token
        if let token = TokenStorage.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = [
            "contactId": contactId,
            "eventType": "recording_consent_given",
            "payload": [
                "callSid": callSid,
                "consentState": consentState,
                "source": "dialer_ios"
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        _ = try? await URLSession.shared.data(for: request)
    }
}
