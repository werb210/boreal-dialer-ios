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

            // BOREAL_DIALER_v803_UI - one large number display. The build showed a
            // static "+1" AND a white "Enter number" field that repeated it; now the
            // big line IS the number as you type ("+1..." when empty). Long-press
            // it to paste a number or copy the one typed.
            Text(displayNumber)
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(number.isEmpty ? Theme.faint : Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .padding(.horizontal, 24)
                .padding(.top, 2)
                .padding(.bottom, 6)
                .contentShape(Rectangle())
                .contextMenu {
                    Button {
                        pasteNumber()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    if !number.isEmpty {
                        Button {
                            UIPasteboard.general.string = number
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                }
                .accessibilityLabel(number.isEmpty ? "No number entered" : "Number \(number)")

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

                // BOREAL_DIALER_v803_UI - solid green 66pt circle, white phone,
                // soft green glow. With nothing to dial it stays green, just dimmer.
                Button {
                    VoiceEngine.shared.startCall(to: number)
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                        .frame(width: 66, height: 66)
                        .background(Circle().fill(Theme.green.opacity(canDial ? 1 : 0.45)))
                        .shadow(color: Theme.green.opacity(canDial ? 0.6 : 0.25), radius: 14)
                }
                .buttonStyle(.plain)
                .disabled(!canDial)
                .accessibilityLabel("Call")

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
        // BOREAL_DIALER_v831_DIALER_POLISH - names the call and its length; the next waiting outcome follows on close
        // (onDismiss also covers a swipe-down).
        .sheet(item: $voiceEngine.finishedCall, onDismiss: { voiceEngine.outcomeSheetClosed() }) { finished in
            CallDispositionSheet(
                callRef: finished.callSid,
                contactName: finished.contactName,
                durationText: finished.durationText
            ) { _ in voiceEngine.finishedCall = nil }
        }
        // BOREAL_DIALER_v817_CALLS - say why a call could not be placed (e.g.
        // microphone access is off) instead of failing silently.
        .alert(
            "Can't place call",
            isPresented: Binding(
                get: { voiceEngine.callError != nil },
                set: { if !$0 { voiceEngine.callError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { voiceEngine.callError = nil }
        } message: {
            Text(voiceEngine.callError ?? "")
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

    // BOREAL_DIALER_v803_UI - same rule the call button always used.
    private var canDial: Bool {
        reachability.isOnline && !number.isEmpty && isIdle
    }

    // BOREAL_DIALER_v803_UI - "+1 (403) 555-0142" once a full North American
    // number is typed, the digits as typed before that, "+1..." when empty.
    private var displayNumber: String {
        if number.isEmpty { return "+1..." }
        let national = PhoneFormat.display(number)
        if national != number && national.hasPrefix("(") { return "+1 " + national }
        return number
    }

    // BOREAL_DIALER_v803_UI - paste keeps only what a dial string can hold.
    private func pasteNumber() {
        guard let raw = UIPasteboard.general.string else { return }
        let cleaned = String(raw.filter { $0.isNumber || $0 == "+" || $0 == "*" || $0 == "#" })
        if !cleaned.isEmpty { number = cleaned }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

// Active call controls — shown when call is in progress
// BOREAL_DIALER_v830_DIALER_CONTROLS - rebuilt from the audit: a working in-call keypad (the button did nothing),
// speaker and audio-route buttons, Hold that resumes a call iOS held, Add / Transfer with a choice between staying on
// the line and handing the call over, and each person's status (ringing, busy, no answer). The "Consent" button,
// which only changed a local flag, is gone; recording can be paused and resumed.
struct ActiveCallControls: View {
    @ObservedObject var voiceEngine = VoiceEngine.shared
    // BOREAL_DIALER_CONFERENCE_CONTROLS_v14
    @ObservedObject var conference = ConferenceSession.shared
    @State private var addParticipantNumber = ""
    @State private var showAddParticipant = false
    @State private var recordingPaused = false

    var body: some View {
        VStack(spacing: 16) {
            if voiceEngine.showKeypad {
                InCallKeypad()
            } else {
                // Main control row
                HStack(spacing: 20) {
                    DialerButton(icon: voiceEngine.isMuted ? "mic.slash.fill" : "mic.slash", label: "Mute", isActive: voiceEngine.isMuted) {
                        voiceEngine.toggleMute()
                    }
                    DialerButton(icon: "circle.grid.3x3.fill", label: "Keypad", isActive: false) {
                        voiceEngine.showKeypad = true
                    }
                    DialerButton(icon: "speaker.wave.2.fill", label: "Speaker", isActive: voiceEngine.isSpeakerOn) {
                        voiceEngine.toggleSpeaker()
                    }
                    AudioRouteButton()
                }

                // Second control row
                HStack(spacing: 20) {
                    // Hold: a call iOS held (e.g. for a mobile call) is resumed; otherwise the other party is held
                    // through the conference API.
                    DialerButton(icon: "pause.circle", label: voiceEngine.isOnHold ? "Resume" : "Hold",
                                 isActive: voiceEngine.isOnHold || conference.remoteOnHold) {
                        if voiceEngine.isOnHold {
                            voiceEngine.resumeFromHold()
                        } else {
                            Task { await conference.setRemoteHold(!conference.remoteOnHold) }
                        }
                    }
                    .disabled(!conference.isActive && !voiceEngine.isOnHold)

                    DialerButton(icon: "person.badge.plus", label: "Add", isActive: showAddParticipant) {
                        showAddParticipant.toggle()
                    }
                    .disabled(!conference.isActive)

                    DialerButton(icon: recordingPaused ? "record.circle" : "pause.rectangle",
                                 label: recordingPaused ? "Resume rec" : "Pause rec",
                                 isActive: recordingPaused, activeColor: .red) {
                        let op = recordingPaused ? "resume" : "pause"
                        Task {
                            await conference.recording(op: op)
                            if conference.lastError == nil { recordingPaused.toggle() }
                        }
                    }
                    .disabled(!conference.isActive)
                }
            }

            // Participants are live from the conference; adding a number joins it.
            if !conference.participants.isEmpty && !voiceEngine.showKeypad {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(conference.participants) { participant in
                        HStack {
                            Image(systemName: "person.circle")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(participant.label)
                                if let status = ActiveCallControls.statusText(participant.status) {
                                    Text(status)
                                        .font(.caption)
                                        .foregroundColor(Theme.muted)
                                }
                            }
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
                            .accessibilityLabel((participant.muted ?? false) ? "Unmute \(participant.label)" : "Mute \(participant.label)")

                            Button {
                                Task { await conference.kick(participantId: participant.id) }
                            } label: {
                                Image(systemName: "person.fill.xmark").foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(participant.label) from the call")
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
            } else if !conference.isActive && !voiceEngine.showKeypad {
                Text("Hold, add and transfer need the call to be placed through Boreal.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

            // Add participant / transfer input
            if showAddParticipant && !voiceEngine.showKeypad {
                VStack(spacing: 8) {
                    TextField("Number to add or transfer to", text: $addParticipantNumber)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.phonePad)

                    HStack(spacing: 8) {
                        Button("Add to call") {
                            let number = addParticipantNumber
                            Task { await conference.addParticipant(phone: number) }
                            addParticipantNumber = ""
                            showAddParticipant = false
                        }
                        .buttonStyle(.borderedProminent)

                        // Warm: they join, you stay to introduce them, then hang up - the call carries on.
                        Button("Transfer, stay on") {
                            let number = addParticipantNumber
                            Task { await conference.transfer(toPhone: number, mode: "warm") }
                            addParticipantNumber = ""
                            showAddParticipant = false
                        }
                        .buttonStyle(.bordered)

                        // Cold: they are rung and you leave the call now.
                        Button("Hand over") {
                            let number = addParticipantNumber
                            Task { await conference.transfer(toPhone: number, mode: "cold") }
                            addParticipantNumber = ""
                            showAddParticipant = false
                        }
                        .buttonStyle(.bordered)
                    }
                    .disabled(!conference.isActive || addParticipantNumber.trimmingCharacters(in: .whitespaces).isEmpty)
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

    // BOREAL_DIALER_v830_DIALER_CONTROLS - a participant's state in words (nil when they are simply on the call).
    nonisolated static func statusText(_ status: String?) -> String? {
        switch (status ?? "").lowercased() {
        case "pending_dial", "invited", "queued", "initiated": return "Calling…"
        case "ringing": return "Ringing…"
        case "busy": return "Busy"
        case "no-answer": return "No answer"
        case "failed": return "Couldn't connect"
        case "left", "canceled", "completed": return "Left the call"
        default: return nil
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


// BOREAL_DIALER_v830_DIALER_CONTROLS - the keypad during a call: tones for phone menus, extensions and PINs.
struct InCallKeypad: View {
    @ObservedObject var voiceEngine = VoiceEngine.shared

    var body: some View {
        VStack(spacing: 12) {
            Text(voiceEngine.sentTones.isEmpty ? " " : voiceEngine.sentTones)
                .font(.system(size: 26, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .accessibilityLabel(voiceEngine.sentTones.isEmpty ? "No tones sent yet" : "Sent \(voiceEngine.sentTones)")
            KeypadGrid(onDigit: { key in
                guard key != "+" else { return }
                voiceEngine.sendTones(key)
            }, onBackspace: {}, onClear: {})
            Button("Hide keypad") { voiceEngine.showKeypad = false }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.greenBright)
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
