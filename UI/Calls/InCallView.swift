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

    private var resolvedFor: String?

    // Best effort: an unresolved number simply shows as a number.
    func resolve(number: String?) async {
        guard let number, !number.isEmpty, resolvedFor != number else { return }
        resolvedFor = number
        do {
            let resolved = try await CallerResolver.resolve(phone: number)
            callerName = resolved.displayName
            callerCompany = resolved.company
        } catch {
            callerName = nil
            callerCompany = nil
        }
    }

    func clear() {
        callerName = nil
        callerCompany = nil
        resolvedFor = nil
    }
}

struct InCallView: View {
    @ObservedObject var voiceEngine = VoiceEngine.shared
    @ObservedObject var conference = ConferenceSession.shared
    @StateObject private var viewModel = InCallViewModel()

    private var number: String? { TwilioVoiceManager.shared.activeNumber }

    private var statusLine: String {
        switch voiceEngine.state {
        case .dialing: return "Calling…"
        case .ringing: return "Ringing…"
        case .active: return formatDuration(voiceEngine.callDuration)
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

            Spacer()

            ActiveCallControls()

            Spacer(minLength: 24)

            Button {
                TwilioVoiceManager.shared.disconnect()
                VoiceEngine.shared.handleDisconnect()
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
