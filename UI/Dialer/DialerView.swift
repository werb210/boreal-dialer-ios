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

            // BOREAL_DIALER_CALLS_PRESENTATION_v23 - country chip and a
            // formatted read-out above the grid.
            HStack(spacing: 8) {
                Text("+1")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))

                Text(number.isEmpty ? "+1…" : PhoneFormat.display(number))
                    .font(.system(size: 30, weight: .regular))
                    .foregroundColor(number.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // BOREAL_DIALER_KEYPAD_ICON_PLIST_v22 - the actual keypad.
            KeypadGrid(
                onDigit: { digit in
                    number.append(digit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                },
                onBackspace: {
                    if !number.isEmpty { number.removeLast() }
                },
                onClear: { number = "" }
            )

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
    // BOREAL_DIALER_CONFERENCE_CONTROLS_v14
    @ObservedObject var conference = ConferenceSession.shared
    @State private var addParticipantNumber = ""
    @State private var showAddParticipant = false

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

                // Hold the remote participant through the conference API.
                DialerButton(icon: "pause.circle", label: "Hold", isActive: conference.remoteOnHold) {
                    Task { await conference.setRemoteHold(!conference.remoteOnHold) }
                }
                .disabled(!conference.isActive)

                // Record
                DialerButton(
                    icon: "pause.rectangle",
                    label: "Pause rec",
                    isActive: false,
                    activeColor: .red
                ) {
                    Task { await conference.recording(op: "pause") }
                }
                .disabled(!conference.isActive || recordingManager.consentState != "granted")

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

                // Keypad
                DialerButton(icon: "rectangle.grid.3x2", label: "Keypad", isActive: false) {
                    voiceEngine.showKeypad.toggle()
                }
            }

            // Participants are live from the conference; adding a number joins it.
            if !conference.participants.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(conference.participants) { participant in
                        HStack {
                            Image(systemName: "person.circle")
                            Text(participant.label)
                            Spacer()
                            Button {
                                Task {
                                    await conference.setMuted(
                                        !(participant.muted ?? false),
                                        participantId: participant.id
                                    )
                                }
                            } label: {
                                Image(systemName: (participant.muted ?? false) ? "mic.slash.fill" : "mic")
                            }
                            .buttonStyle(.borderless)

                            Button {
                                Task { await conference.kick(participantId: participant.id) }
                            } label: {
                                Image(systemName: "person.fill.xmark").foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal)
                    }
                }
            }

            if let message = conference.lastError {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            } else if !conference.isActive {
                Text("Call controls need the call to be placed through the server.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

            // Add participant input
            if showAddParticipant {
                HStack {
                    TextField("Enter number or search...", text: $addParticipantNumber)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.phonePad)

                    Button("Add") {
                        let number = addParticipantNumber
                        Task { await conference.addParticipant(phone: number) }
                        addParticipantNumber = ""
                        showAddParticipant = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!conference.isActive)

                    Button("Transfer") {
                        let number = addParticipantNumber
                        Task { await conference.transfer(toPhone: number, mode: "warm") }
                        addParticipantNumber = ""
                        showAddParticipant = false
                    }
                    .buttonStyle(.bordered)
                    .disabled(!conference.isActive)
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


// BOREAL_DIALER_KEYPAD_ICON_PLIST_v22
// The 3x4 grid, letters and all, matching the concept mockup. Long-pressing 0
// gives +, which matters because every server-side number is E.164.
struct KeypadGrid: View {
    var onDigit: (String) -> Void
    var onBackspace: () -> Void
    var onClear: () -> Void

    private let keys: [[(String, String)]] = [
        [("1", ""), ("2", "ABC"), ("3", "DEF")],
        [("4", "GHI"), ("5", "JKL"), ("6", "MNO")],
        [("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ")],
        [("*", ""), ("0", "+"), ("#", "")],
    ]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(keys.indices, id: \.self) { row in
                HStack(spacing: 26) {
                    ForEach(keys[row], id: \.0) { key, letters in
                        Button {
                            onDigit(key)
                        } label: {
                            // BOREAL_DIALER_THEME_v27
                            VStack(spacing: -2) {
                                Text(key)
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundColor(Theme.text)
                                if !letters.isEmpty {
                                    Text(letters)
                                        .font(.system(size: 9, weight: .bold))
                                        .kerning(2)
                                        .foregroundColor(Theme.faint)
                                }
                            }
                            .frame(width: 66, height: 66)
                            .overlay(Circle().stroke(Theme.line2, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            LongPressGesture().onEnded { _ in
                                if key == "0" { onDigit("+") }
                            }
                        )
                    }
                }
            }

            HStack {
                Spacer()
                Button(action: onBackspace) {
                    Image(systemName: "delete.left").font(.title2)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(LongPressGesture().onEnded { _ in onClear() })
                .padding(.trailing, 34)
            }
        }
        .padding(.vertical, 8)
    }
}
