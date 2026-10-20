// BOREAL_DIALER_v830_DIALER_CONTROLS - when this iPhone cannot receive calls (no calling token from BF-Server, or the
// Twilio push registration failed or never happened), say so at the top of the app with a Retry. It used to fail
// silently: calls went to voicemail and nothing on screen said why.
import SwiftUI

struct CallReadinessBanner: View {
    @ObservedObject private var voice = VoiceManager.shared
    @ObservedObject private var engine = VoiceEngine.shared
    @State private var retrying = false

    /// Short setup gaps (launch, a token refresh) are normal; only a lasting one is shown.
    nonisolated static let graceSeconds: TimeInterval = 20

    nonisolated static func shouldShow(notReceivingSince: Date?, callIdle: Bool, now: Date = Date()) -> Bool {
        guard callIdle, let since = notReceivingSince else { return false }
        return now.timeIntervalSince(since) >= graceSeconds
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            if CallReadinessBanner.shouldShow(notReceivingSince: voice.notReceivingSince, callIdle: engine.isIdle, now: context.date) {
                HStack(spacing: 10) {
                    Image(systemName: "phone.badge.exclamationmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.away)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You won't receive calls right now")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.text)
                        Text(voice.lastSetupFailed ? "Couldn't connect to the phone service. Check your signal." : "Still connecting to the phone service.")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.muted)
                    }
                    Spacer(minLength: 6)
                    Button(retrying ? "Retrying…" : "Retry") {
                        retrying = true
                        VoiceManager.shared.recoverIfNeeded()
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            retrying = false
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .buttonStyle(.bordered)
                    .tint(Theme.greenBright)
                    .disabled(retrying)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface2)
                .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.away.opacity(0.6)), alignment: .bottom)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
