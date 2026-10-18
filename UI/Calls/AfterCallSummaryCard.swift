// BOREAL_DIALER_v821 - the "Call summary" card: shown on the call-ended sheet, from the Calls > Recents banner for the
// call that just ended, and from a Recents row's menu. It polls GET /calls/{callSid}/summary every 5 s for up to 2 min
// while the server says "pending", then shows the summary, next steps, "Open contact" and "Task created".
import SwiftUI

@MainActor
final class AfterCallSummaryViewModel: ObservableObject {
    @Published private(set) var phase: AfterCallSummaryPoller.Phase = .waiting

    /// Cancelled with the view's task (sheet closed, card scrolled away).
    func run(callSid: String) async {
        var poller = AfterCallSummaryPoller(startedAt: Date())
        phase = .waiting
        while poller.shouldPoll(now: Date()) {
            let result: AfterCallSummary?
            do {
                result = try await AfterCallSummaryService.fetch(callSid: callSid)
            } catch {
                // Transient (no signal, 404 while the server catches up): keep polling until the time limit.
                if Task.isCancelled { return }
                result = nil
            }
            poller.apply(result, now: Date())
            phase = poller.phase
            if poller.isFinished { return }
            do {
                try await Task.sleep(nanoseconds: AfterCallSummaryPoller.intervalNanoseconds)
            } catch {
                return
            }
        }
        poller.expireIfNeeded(now: Date())
        phase = poller.phase
    }
}

/// BOREAL_DIALER_v821 - a contact to open from the card.
struct SummaryContactLink: Identifiable, Equatable {
    let id: String
    let name: String?
}

struct AfterCallSummaryCard: View {
    let callSid: String
    @StateObject private var model = AfterCallSummaryViewModel()
    @State private var openContact: SummaryContactLink?
    @State private var voiceNote: VoiceNoteTarget? // BOREAL_DIALER_v823_VOICE_NOTES

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(Theme.greenBright)
                Text("Call summary")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                if model.phase == .waiting {
                    ProgressView()
                }
            }
            content
        }
        .padding(.vertical, 4)
        .task(id: callSid) { await model.run(callSid: callSid) }
        .sheet(item: $voiceNote) { target in VoiceNoteSheet(target: target) } // BOREAL_DIALER_v823_VOICE_NOTES
        .sheet(item: $openContact) { link in
            NavigationStack {
                ContactDetailView(
                    contact: CRMContact(id: link.id, name: link.name, firstName: nil, lastName: nil, email: nil,
                                        phone: nil, companyName: nil, leadStatus: nil),
                    onMessage: {}
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { openContact = nil }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .waiting:
            Text("Writing the summary from the call transcript. This usually takes under a minute.")
                .font(.system(size: 13))
                .foregroundColor(Theme.muted)
        case .unavailable:
            Text("No summary for this call.")
                .font(.system(size: 13))
                .foregroundColor(Theme.muted)
        case .timedOut:
            Text("The summary isn't ready yet. It will be saved to the contact's timeline when it is.")
                .font(.system(size: 13))
                .foregroundColor(Theme.muted)
        case .ready(let result):
            readyContent(result)
        }
    }

    @ViewBuilder
    private func readyContent(_ result: AfterCallSummary) -> some View {
        if let name = result.contactName {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.muted)
        }
        if let summary = result.summary {
            Text(summary)
                .font(.system(size: 14))
                .foregroundColor(Theme.text)
                .textSelection(.enabled)
        }
        if !result.nextSteps.isEmpty {
            Text("Next steps")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.faint)
                .padding(.top, 2)
            ForEach(Array(result.nextSteps.enumerated()), id: \.offset) { _, step in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.greenBright)
                    Text(step)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.text)
                }
            }
        }
        HStack(spacing: 12) {
            if result.taskCreated {
                Label("Task created", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.greenBright)
            }
            Spacer()
            // BOREAL_DIALER_v823_VOICE_NOTES - dictate a note for this client straight after the call.
            if let contactId = result.contactId {
                Button {
                    voiceNote = VoiceNoteTarget(contactId: contactId, name: result.contactName)
                } label: {
                    Label("Voice note", systemImage: "mic")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
            }
            if let contactId = result.contactId {
                Button {
                    openContact = SummaryContactLink(id: contactId, name: result.contactName)
                } label: {
                    Label("Open contact", systemImage: "person.crop.circle")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 2)
    }
}

/// BOREAL_DIALER_v821 - the card on its own, for Recents (banner and row menu).
struct AfterCallSummarySheet: View {
    let callSid: String
    let title: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                AfterCallSummaryCard(callSid: callSid)
                    .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(title ?? "Call summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// BOREAL_DIALER_v821 - Calls > Recents banner for the call that just ended.
struct AfterCallSummaryBanner: View {
    @ObservedObject private var store = AfterCallSummaryStore.shared
    @State private var showing: FinishedCall?

    var body: some View {
        // Wrapped in a VStack so the sheet modifier sits on a container, not on the brace of the `if`.
        VStack(spacing: 0) {
            if let call = store.bannerCall() {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundColor(Theme.greenBright)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Call summary")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.text)
                        Text("Your last call, \(call.endedAt, style: .relative) ago")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.muted)
                    }
                    Spacer()
                    Button("View") { showing = call }
                        .buttonStyle(.bordered)
                    Button {
                        store.dismissedCallSid = call.callSid
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss call summary")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.surface)
            }
        }
        .sheet(item: $showing) { call in
            AfterCallSummarySheet(callSid: call.callSid, title: nil)
        }
    }
}
