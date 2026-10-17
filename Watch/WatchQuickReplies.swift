// BOREAL_DIALER_v821 - quick replies on the Watch. Replying to a text or client message (a notification's "Quick reply"
// button, a tap on an SMS / client-message / handoff notification, or Text on a contact) shows the list from
// GET /templates/quick?channel=sms, snippets first, plus dictation / Scribble. One tap sends:
//   - a text goes out through POST /watch/sms (works without the iPhone), else through the iPhone, which posts
//     /communications/sms {to, body, contactId};
//   - a client-portal message needs the staff session, so the iPhone posts /communications/messages/send {contactId, body}.
// The list is cached for a day.
import Foundation
import SwiftUI
import UserNotifications
import WatchKit

/// BOREAL_DIALER_v821 - who a Watch reply goes to.
enum WatchReplyTarget: Equatable {
    case sms(phone: String, contactId: String?, name: String?)
    case portal(contactId: String, name: String?)

    var title: String {
        switch self {
        case .sms(let phone, _, let name): return name ?? phone
        case .portal(_, let name): return name ?? "Client message"
        }
    }

    /// The reply target for an alert, using the same rules as the notification Reply (BorealAlertReplyTarget).
    static func from(payload: BorealAlertPayload, name: String?) -> WatchReplyTarget? {
        let cleanName = name.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        switch BorealAlertReplyTarget.target(for: payload) {
        case .sms(let phone, let contactId)?: return .sms(phone: phone, contactId: contactId, name: cleanName)
        case .portalMessage(let contactId)?: return .portal(contactId: contactId, name: cleanName)
        case nil: return nil
        }
    }

    /// What the iPhone needs to send it (the alert-reply relay, BOREAL_DIALER_v820_WATCH).
    func relayMessage(body: String) -> WatchAlertReplyMessage {
        switch self {
        case .sms(let phone, let contactId, _):
            return WatchAlertReplyMessage(kind: BorealAlertKind.sms.rawValue, contactId: contactId, phone: phone,
                                          threadKind: "sms", body: body)
        case .portal(let contactId, _):
            return WatchAlertReplyMessage(kind: BorealAlertKind.clientMessage.rawValue, contactId: contactId, phone: nil,
                                          threadKind: "messages", body: body)
        }
    }
}

/// BOREAL_DIALER_v821 - a tapped VOICEMAIL alert on the Watch: the whole transcript and a Call back button.
struct WatchVoicemailAlert: Equatable {
    let caller: String
    let text: String
    let phone: String?
}

/// BOREAL_DIALER_v821 - the extra Watch-only action on reply-able alerts. Foreground, so it opens the quick-reply list.
enum WatchQuickReplyAction {
    static let identifier = "QUICK_REPLY"

    static func action() -> UNNotificationAction {
        UNNotificationAction(identifier: identifier, title: "Quick reply", options: [.foreground])
    }

    /// The shared category plus Quick reply for the kinds that take a reply; Call back categories are unchanged.
    static func category(for kind: BorealAlertKind) -> UNNotificationCategory {
        let shared = BorealAlertCategories.category(for: kind)
        guard !kind.offersCallBack else { return shared }
        return UNNotificationCategory(identifier: shared.identifier, actions: shared.actions + [action()],
                                      intentIdentifiers: [], options: [])
    }
}

/// BOREAL_DIALER_v821 - loads the quick replies: cache when fresh, else /templates/quick, else the older
/// /watch/sms-templates list, else whatever the cache still holds.
struct WatchQuickReplyService {
    let cache: QuickReplyCache
    let makeClient: () throws -> WatchAPIClient

    init(cache: QuickReplyCache = QuickReplyCache(),
         makeClient: @escaping () throws -> WatchAPIClient = { try WatchAPIClient() }) {
        self.cache = cache
        self.makeClient = makeClient
    }

    func load(force: Bool = false, now: Date = Date()) async -> [QuickReply] {
        let cached = cache.load(now: now)
        if !force, let cached, cached.fresh, !cached.items.isEmpty { return cached.items }
        if let fetched = try? await fetchQuick(), !fetched.isEmpty {
            cache.store(fetched, at: now)
            return QuickReplyOrdering.ordered(fetched)
        }
        if let legacy = try? await fetchLegacy(), !legacy.isEmpty {
            return QuickReplyOrdering.ordered(legacy)
        }
        return cached?.items ?? []
    }

    private func fetchQuick() async throws -> [QuickReply] {
        let api = try makeClient()
        let data = try await api.request(path: "/templates/quick", query: [URLQueryItem(name: "channel", value: "sms")])
        return try JSONDecoder().decode(QuickReplyEnvelope.self, from: data).items
    }

    /// GET /watch/sms-templates {templates: [{id, name, body}]} - the list Quick Text used before v821.
    private func fetchLegacy() async throws -> [QuickReply] {
        let api = try makeClient()
        let data = try await api.request(path: "/watch/sms-templates")
        return try JSONDecoder().decode(QuickReplyEnvelope.self, from: data).items
    }
}

/// BOREAL_DIALER_v821 - sends one reply from the Watch.
enum WatchReplySender {
    enum Outcome: Equatable {
        /// Boreal accepted it from the Watch.
        case sent
        /// Handed to the iPhone, which sends it (now if reachable, otherwise when it next is).
        case viaIPhone
    }

    @MainActor
    static func send(_ text: String, to target: WatchReplyTarget,
                     sms: any WatchSMSService = DirectWatchSMSService()) async -> Outcome? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        if case .sms(let phone, _, _) = target {
            do {
                try await sms.send(to: phone, body: body)
                return .sent
            } catch {
                // Not linked or offline: let the iPhone send it.
            }
        }
        WatchCompanionLink.sendReply(target.relayMessage(body: body))
        return .viaIPhone
    }
}

/// BOREAL_DIALER_v821 - the reply screen: dictation / Scribble first, then the quick replies.
struct WatchQuickReplyView: View {
    let target: WatchReplyTarget
    @Environment(\.dismiss) private var dismiss
    @State private var replies: [QuickReply] = []
    @State private var loading = true
    @State private var sending = false
    @State private var status: String?

    var body: some View {
        List {
            Text(target.title).font(.headline).lineLimit(2)
            TextFieldLink(prompt: Text("Message")) {
                Label("Dictate or Scribble", systemImage: "mic.fill")
            } onSubmit: { text in
                send(text)
            }
            .disabled(sending)
            if loading { ProgressView() }
            if !loading && replies.isEmpty {
                Text("No quick replies yet. Add snippets in the Boreal portal.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(replies) { reply in
                Button {
                    send(reply.body)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(reply.name).lineLimit(1)
                            if reply.isSnippet {
                                Image(systemName: "bolt.fill")
                                    .font(.caption2)
                                    .foregroundStyle(WatchTheme.greenBright)
                            }
                        }
                        Text(reply.body).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                .disabled(sending)
            }
            if let status { Text(status).font(.caption2).foregroundStyle(.secondary) }
        }
        .navigationTitle("Reply")
        .task {
            replies = await WatchQuickReplyService().load()
            loading = false
        }
    }

    private func send(_ text: String) {
        guard !sending else { return }
        sending = true
        status = "Sending…"
        Task { @MainActor in
            let outcome = await WatchReplySender.send(text, to: target)
            sending = false
            switch outcome {
            case .sent?:
                WKInterfaceDevice.current().play(.success)
                dismiss()
            case .viaIPhone?:
                WKInterfaceDevice.current().play(.success)
                status = "Sending from your iPhone."
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                dismiss()
            case nil:
                status = "Type or pick a message first."
            }
        }
    }
}

/// BOREAL_DIALER_v821 - a tapped voicemail alert: the full text (long transcripts are cut off in the banner) and Call back.
struct WatchVoicemailAlertView: View {
    let alert: WatchVoicemailAlert
    @StateObject private var call = WatchCallController()

    var body: some View {
        List {
            Text(alert.caller).font(.headline)
            Text(alert.text).font(.body)
            if let phone = alert.phone {
                Button {
                    call.start(CallRequest(destination: phone, line: .BF))
                } label: {
                    Label("Call back", systemImage: "phone.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.green)
                .disabled(call.isSettingUp)
                WatchCallStatusView(controller: call)
            }
        }
        .navigationTitle("Voicemail")
    }
}
