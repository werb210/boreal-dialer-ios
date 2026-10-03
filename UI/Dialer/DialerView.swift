import SwiftUI
import UIKit

struct DialerView: View {

    @State private var number = ""
    @ObservedObject private var voiceEngine = VoiceEngine.shared
    @ObservedObject private var reachability = ReachabilityManager.shared
    @ObservedObject private var recordingManager = RecordingManager.shared
    @ObservedObject private var deepLinks = DeepLinkCoordinator.shared
    @State private var contactContext: String?

    // BOREAL_DIALER_MOCKUP_LAYOUT_v60 - laid out like the concept mockup: number,
    // Quick Call, keypad, then all three call actions. Scrolling prevents smaller
    // iPhones from compressing the keys and call button.
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 0) {

            if recordingManager.isRecording {
                Text("Call is being recorded")
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
            }

            Text("ENTER A NUMBER")
                .font(.system(size: 12, weight: .regular))
                .kerning(1.5)
                .foregroundColor(Theme.faint)
                .padding(.top, 8)

            Text("+1")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(Theme.text)
                .padding(.top, 2)
                .padding(.bottom, 8)

                // BOREAL_DIALER_TEAM_ROSTER_SELF_v50 - the placeholder used to
                // read "+1…" while the chip immediately to its left already
                // reads "+1", so an empty keypad showed the country code twice.
                // PhoneFormat.display returns the national format with no
                // country code, so the chip is the thing carrying that
                // information and the placeholder should not repeat it.
            Text(number.isEmpty ? "Enter number" : PhoneFormat.display(number))
                .font(.system(size: 18, weight: number.isEmpty ? .regular : .medium))
                .foregroundColor(number.isEmpty ? Color(hex: 0x9AA2FF) : Color(hex: 0x0A0B0D))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 13).fill(Color.white))
                .padding(.horizontal, 18)

            QuickCallRow()

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
            .padding(.horizontal, 40)
            .padding(.top, 18)

            HStack(spacing: 46) {
                Button {
                    if !number.isEmpty { number.removeLast() }
                } label: {
                    Text("Delete").font(.system(size: 14)).foregroundColor(Theme.muted).frame(width: 54)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(LongPressGesture().onEnded { _ in number = "" })

                Button {
                    VoiceEngine.shared.startCall(to: number)
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 26))
                        .foregroundColor(Theme.onGreen)
                        .frame(width: 66, height: 66)
                        .background(Circle().fill(
                            (!reachability.isOnline || number.isEmpty || !isIdle)
                                ? Theme.surface3 : Theme.green
                        ))
                        .shadow(color: Theme.green.opacity(number.isEmpty ? 0 : 0.55), radius: 14)
                }
                .buttonStyle(.plain)
                .disabled(!reachability.isOnline || number.isEmpty || !isIdle)

                Button { number = "" } label: {
                    Text("Clear").font(.system(size: 14)).foregroundColor(Theme.muted).frame(width: 54)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
            .padding(.bottom, 8)

            if !reachability.isOnline {
                Text("Offline: calling disabled")
                    .foregroundColor(.orange)
                    .padding(.bottom, 8)
            }

        }
        }
        .onAppear { applyPendingDeepLink() }
        .onChange(of: deepLinks.pending) { _ in applyPendingDeepLink() }
        // BOREAL_DIALER_IN_CALL_SCREEN_v37 - a live call takes the screen.
        .overlay {
            if !isIdle {
                InCallView()
            }
        }
        // BOREAL_DIALER_PRESENT_DISPOSITION_v224
        .sheet(item: $voiceEngine.finishedCall) { finished in
            CallDispositionSheet(
                callRef: finished.callSid,
                contactName: nil,
                durationText: nil
            ) { _ in voiceEngine.finishedCall = nil }
        }
    }

    private func applyPendingDeepLink() {
        guard let link = deepLinks.consumeWhenAuthenticated() else { return }
        switch link {
        case .newCall:
            number = ""
        case .phone(let phone, let start):
            number = phone
            if start, isIdle { VoiceEngine.shared.startCall(to: phone) }
        case .contact(let id, _):
            // No verified direct contact-by-id client contract exists. Preserve
            // the safe context without inventing a request or auto-dialling.
            contactContext = id
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

        }
        .frame(maxWidth: .infinity)
    }
}
