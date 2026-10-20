// BOREAL_DIALER_IN_CALL_SCREEN_v37
// A call in progress used to be three bare Text views stacked under the keypad:
// "On call with +15875551234", a timer, the controls, and a red "End Call". No
// caller name, no state, and the keypad still underneath it.
//
// This is the full-screen call, covering the keypad while a call is up. The
// name comes from POST /api/voice/resolve-caller, which is what the portal uses
// to turn a number into a contact - so an inbound call from a known client
// shows their name rather than their number.
// BOREAL_DIALER_RESOLVE_CALLER_CONTRACT_v45
import SwiftUI

@MainActor
final class InCallViewModel: ObservableObject {
    @Published var callerName: String?
    @Published var callerCompany: String?
    // BOREAL_DIALER_v821 - the caller card fetched here (outgoing calls, or an incoming call nothing named yet).
    @Published var card: CallerCard?

    private var resolvedFor: String?

    // Best effort: an unresolved number simply shows as a number.
    // BOREAL_DIALER_v821 - a card already known for this call (invite parameters or the ringing lookup) is used as is;
    // otherwise GET /voice/caller-card, and the v45 resolve-caller lookup only if that fails.
    func resolve(number: String?) async {
        guard let number, !number.isEmpty, resolvedFor != number else { return }
        resolvedFor = number
        if let known = CallerCardStore.shared.card(for: number) {
            apply(known)
            return
        }
        if let fetched = try? await CallerCardService.fetch(phone: number), fetched.isDisplayable {
            guard resolvedFor == number else { return }
            CallerCardStore.shared.set(fetched, handle: number)
            apply(fetched)
            return
        }
        do {
            let resolved = try await CallerResolver.resolve(phone: number)
            guard resolvedFor == number else { return }
            callerName = resolved.displayName
            callerCompany = resolved.company
        } catch {
            callerName = nil
            callerCompany = nil
        }
    }

    // BOREAL_DIALER_v821
    func apply(_ card: CallerCard) {
        self.card = card
        callerName = card.name
        callerCompany = card.company
    }

    func clear() {
        callerName = nil
        callerCompany = nil
        card = nil
        resolvedFor = nil
    }
}

struct InCallView: View {
    @ObservedObject var voiceEngine = VoiceEngine.shared
    @ObservedObject var conference = ConferenceSession.shared
    @StateObject private var viewModel = InCallViewModel()
    // BOREAL_DIALER_v821 - a card that lands while the call is up (the ringing lookup finishing late) shows at once.
    @ObservedObject private var cardStore = CallerCardStore.shared
    @State private var crmContact: SummaryContactLink?

    private var card: CallerCard? { cardStore.card(for: number) ?? viewModel.card }

    private var number: String? { TwilioVoiceManager.shared.activeNumber }

    private var statusLine: String {
        switch voiceEngine.state {
        // BOREAL_DIALER_v829_RELIABILITY - "Ringing…" once their phone rings; "Connecting…" between Answer and audio.
        case .dialing: return voiceEngine.remoteRinging ? "Ringing…" : "Calling…"
        case .ringing: return "Ringing…"
        case .active:
            // BOREAL_DIALER_v830_DIALER_CONTROLS - a signal drop or a hold is not a dead call: say which it is.
            if voiceEngine.isReconnecting { return "Reconnecting…" }
            if voiceEngine.isOnHold { return "On hold · " + formatDuration(voiceEngine.callDuration) }
            return voiceEngine.isConnecting ? "Connecting…" : formatDuration(voiceEngine.callDuration)
        case .ended: return "Call ended"
        case .failed: return "Call failed"
        case .idle: return ""
        }
    }

    private var isConnected: Bool {
        if case .active = voiceEngine.state { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            VStack(spacing: 14) {
                AvatarCircle(name: viewModel.callerName ?? PhoneFormat.display(number).ifEmpty("Unknown"), size: 96)

                Text(viewModel.callerName ?? PhoneFormat.display(number).ifEmpty("Unknown"))
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .multilineTextAlignment(.center)

                if let company = viewModel.callerCompany, !company.isEmpty {
                    Text(company)
                        .font(.system(size: 15))
                        .foregroundColor(Theme.muted)
                }

                // The number stays visible even when a name resolved - staff
                // read it back to clients constantly.
                if viewModel.callerName != nil, let number, !number.isEmpty {
                    Text(PhoneFormat.display(number))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.faint)
                }

                Text(statusLine)
                    .font(.system(size: 17, design: isConnected ? .monospaced : .default))
                    .foregroundColor(isConnected ? Theme.greenBright : Theme.muted)
            }

            // BOREAL_DIALER_v821 - who this is, where they are in the pipeline, and what was said last time.
            if let card, card.isDisplayable {
                CallerCardView(card: card) { contactId in
                    crmContact = SummaryContactLink(id: contactId, name: card.name)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }

            Spacer()

            ActiveCallControls()

            Spacer(minLength: 24)

            Button {
                // BOREAL_DIALER_v817_CALLS - hang up through CallKit
                // (CXEndCallAction), which disconnects the Twilio leg; ending
                // only the Twilio leg left CallKit holding a stale call.
                VoiceEngine.shared.hangUp()
                conference.clear()
                viewModel.clear()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Theme.red))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .task(id: number) { await viewModel.resolve(number: number) }
        // BOREAL_DIALER_v821 - "Open in CRM": the contact record over the call screen; the call keeps going.
        .sheet(item: $crmContact) { link in
            NavigationStack {
                ContactDetailView(
                    contact: CRMContact(id: link.id, name: link.name, firstName: nil, lastName: nil, email: nil,
                                        phone: number, companyName: card?.company, leadStatus: nil),
                    onMessage: {}
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back to call") { crmContact = nil }
                    }
                }
            }
        }
    }
}

// BOREAL_DIALER_v821 - the caller card on the in-call screen.
struct CallerCardView: View {
    let card: CallerCard
    var onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let stage = card.stage {
                    Text(stage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.onGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.greenBright))
                        .accessibilityLabel("Stage \(stage)")
                }
                ForEach(Array(card.tags.prefix(2)), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().stroke(Theme.line2, lineWidth: 1))
                }
                Spacer(minLength: 0)
            }
            if let note = card.lastNote {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last note")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.faint)
                    Text(note)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.text)
                        .lineLimit(4)
                }
            }
            if let contactId = card.contactId {
                Button {
                    onOpen(contactId)
                } label: {
                    Label("Open in CRM", systemImage: "person.text.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.greenBright)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface2))
    }
}

private func formatDuration(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    if m >= 60 {
        return String(format: "%d:%02d:%02d", m / 60, m % 60, s)
    }
    return String(format: "%d:%02d", m, s)
}
