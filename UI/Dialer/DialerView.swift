import SwiftUI
import UIKit

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
            VStack(spacing: 16) {
                Text("On call with \(TwilioVoiceManager.shared.activeNumber ?? "")")
                Text(formatDuration(voiceEngine.callDuration))
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)

                ActiveCallControls()

                Button("End Call") {
                    TwilioVoiceManager.shared.disconnect()
                    VoiceEngine.shared.handleDisconnect()
                }
                .foregroundColor(.red)
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

// Active call controls — shown when call is in progress
struct ActiveCallControls: View {
    @ObservedObject var voiceEngine = VoiceEngine.shared
    @ObservedObject var recordingManager = RecordingManager.shared
    @State private var onHold = false
    @State private var addParticipantNumber = ""
    @State private var showAddParticipant = false
    @State private var participants: [String] = []

    var body: some View {
        VStack(spacing: 16) {
            // Main control row
            HStack(spacing: 20) {
                // Mute
                DialerButton(
                    icon: "mic.slash",
                    label: "Mute",
                    isActive: voiceEngine.isMuted
                ) {
                    voiceEngine.toggleMute()
                }

                // Hold
                DialerButton(icon: "pause.circle", label: "Hold", isActive: onHold) {
                    onHold.toggle()
                    voiceEngine.toggleHold(onHold: onHold)
                }

                // Record
                DialerButton(
                    icon: "record.circle",
                    label: "Record",
                    isActive: recordingManager.isRecording,
                    activeColor: .red
                ) {
                    Task {
                        if recordingManager.isRecording {
                            try? await recordingManager.stopRecording(callSid: voiceEngine.activeCallSid ?? "")
                        } else {
                            try? await recordingManager.startRecording(callSid: voiceEngine.activeCallSid ?? "")
                        }
                    }
                }

                // Recording consent
                DialerButton(
                    icon: "checkmark.seal",
                    label: "Consent",
                    isActive: recordingManager.consentState == "granted"
                ) {
                    recordingManager.setConsentState("granted")
                }
            }

            // Second control row
            HStack(spacing: 20) {
                // Transfer
                DialerButton(icon: "arrow.right.circle", label: "Transfer", isActive: false) {
                    showAddParticipant = true
                }

                // Add participant
                DialerButton(icon: "person.badge.plus", label: "Add", isActive: false) {
                    showAddParticipant = true
                }

                // Park
                DialerButton(icon: "car.fill", label: "Park", isActive: false) {
                    Task { try? await parkCall() }
                }

                // Keypad
                DialerButton(icon: "rectangle.grid.3x2", label: "Keypad", isActive: false) {
                    voiceEngine.showKeypad.toggle()
                }
            }

            // Participants list
            if !participants.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(participants, id: \.self) { participant in
                        HStack {
                            Image(systemName: "person.circle")
                            Text(participant)
                            Spacer()
                            Image(systemName: "mic")
                            Image(systemName: "speaker.wave.1")
                        }
                        .padding(.horizontal)
                    }

                    Button("Start Conference") {
                        Task { try? await startConference() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .padding(.horizontal)
                }
            }

            // Add participant input
            if showAddParticipant {
                HStack {
                    TextField("Enter number or search...", text: $addParticipantNumber)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.phonePad)

                    Button("Add") {
                        Task { try? await addParticipant(addParticipantNumber) }
                        addParticipantNumber = ""
                        showAddParticipant = false
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Transfer") {
                        Task { try? await transferCall(to: addParticipantNumber) }
                        showAddParticipant = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }

            // Smart reply suggestions
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(smartReplies, id: \.self) { reply in
                        Button(reply) {
                            // Copy to clipboard or display
                            UIPasteboard.general.string = reply
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private let smartReplies = [
        "Let me look into that for you",
        "I'll get in touch with the team",
        "I'll review and get back to you",
        "Can I put you on a brief hold?",
        "Let me check that right now"
    ]

    private func parkCall() async throws {
        guard let callSid = VoiceEngine.shared.activeCallSid,
              let url = URL(string: "\(APIConfig.baseURL)/telephony/park") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = TokenStorage.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONEncoder().encode(["callSid": callSid])
        _ = try await URLSession.shared.data(for: request)
    }

    private func addParticipant(_ number: String) async throws {
        guard let callSid = VoiceEngine.shared.activeCallSid,
              let url = URL(string: "\(APIConfig.baseURL)/telephony/conference/add") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = TokenStorage.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONEncoder().encode(["callSid": callSid, "to": number])
        _ = try await URLSession.shared.data(for: request)
        participants.append(number)
    }

    private func transferCall(to number: String) async throws {
        guard let callSid = VoiceEngine.shared.activeCallSid,
              let url = URL(string: "\(APIConfig.baseURL)/telephony/transfer") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = TokenStorage.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONEncoder().encode(["callSid": callSid, "to": number])
        _ = try await URLSession.shared.data(for: request)
    }

    private func startConference() async throws {
        guard let callSid = VoiceEngine.shared.activeCallSid,
              let url = URL(string: "\(APIConfig.baseURL)/telephony/conference/start") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = TokenStorage.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONEncoder().encode(["callSid": callSid, "participants": participants])
        _ = try await URLSession.shared.data(for: request)
    }
}

// Reusable dialer button component
struct DialerButton: View {
    let icon: String
    let label: String
    var isActive: Bool = false
    var activeColor: Color = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(label)
                    .font(.caption2)
            }
            .frame(width: 60, height: 60)
            .background(isActive ? activeColor.opacity(0.2) : Color(.systemGray6))
            .foregroundColor(isActive ? activeColor : .primary)
            .cornerRadius(12)
        }
    }
}
