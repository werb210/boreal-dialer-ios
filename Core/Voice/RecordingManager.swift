import Foundation

@MainActor
final class RecordingManager: ObservableObject {

    static let shared = RecordingManager()

    @Published private(set) var isRecording = false
    @Published private(set) var consentState: String = "unknown"

    private init() {}

    func setConsentState(_ value: String) {
        consentState = value
        Telemetry.event("recording_consent_updated", metadata: ["state": value])
    }

    func startRecording(callSid: String) async throws {
        try await API.startRecording(callSid: callSid)
        isRecording = true
        Telemetry.event("recording_started", metadata: ["callSid": callSid, "consent": consentState])
    }

    func stopRecording(callSid: String) async throws {
        try await API.stopRecording(callSid: callSid)
        isRecording = false
        Telemetry.event("recording_stopped", metadata: ["callSid": callSid])
    }
}
