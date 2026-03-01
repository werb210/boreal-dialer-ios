import SwiftUI

struct DialerView: View {

    @State private var number = ""
    @ObservedObject private var voiceEngine = VoiceEngine.shared
    @ObservedObject private var reachability = ReachabilityManager.shared
    @ObservedObject private var recordingManager = RecordingManager.shared

    var body: some View {
        VStack(spacing: 20) {

            if recordingManager.isRecording {
                Text("Call is being recorded")
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
            }

            TextField("Enter phone number", text: $number)
                .keyboardType(.phonePad)
                .textFieldStyle(.roundedBorder)

            Button("Call") {
                VoiceEngine.shared.startCall(to: number)
            }
            .disabled(!reachability.isOnline || number.isEmpty || !isIdle)

            if !reachability.isOnline {
                Text("Offline: calling disabled")
                    .foregroundColor(.orange)
            }

            callStatusView()

        }
        .padding()
    }

    @ViewBuilder
    private func callStatusView() -> some View {
        switch voiceEngine.state {
        case .idle:
            EmptyView()
        case .dialing:
            Text("Dialing...")
        case .ringing:
            Text("Ringing...")
        case .active:
            VStack {
                Text("On call with \(TwilioVoiceManager.shared.activeNumber ?? "")")
                Text(formatDuration(voiceEngine.callDuration))
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                Button("End Call") {
                    TwilioVoiceManager.shared.disconnect()
                    VoiceEngine.shared.handleDisconnect()
                }
                .foregroundColor(.red)

                if recordingManager.isRecording {
                    Button("Stop Recording") {
                        Task {
                            if case .active(let uuid) = voiceEngine.state {
                                try? await recordingManager.stopRecording(callSid: uuid.uuidString)
                            }
                        }
                    }
                } else {
                    Button("Start Recording") {
                        Task {
                            if case .active(let uuid) = voiceEngine.state {
                                recordingManager.setConsentState("announced")
                                try? await recordingManager.startRecording(callSid: uuid.uuidString)
                            }
                        }
                    }
                }
            }
        case .ended:
            Text("Call Ended")
        case .failed:
            Text("Call Failed")
                .foregroundColor(.red)
        }
    }

    private var isIdle: Bool {
        if case .idle = voiceEngine.state {
            return true
        }
        return false
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}
