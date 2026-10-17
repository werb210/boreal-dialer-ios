// BOREAL_DIALER_MESSAGES_THREAD_v10
// BOREAL_DIALER_v817_MESSAGING - the Messages tab now matches the staff portal's
// Messages tab exactly: client-portal chats and "talk to a person" requests,
// one conversation per contact. SMS lives only in the SMS tab, so the old
// "Unified inbox" with All / Unread / SMS / Chat / Email filters is gone.
//
// Same endpoints the portal uses:
//   GET  /communications/messages-list?q=           -> { conversations: [...] }
//   GET  /communications/messages/thread?contactId= -> [ ...messages ]
//   POST /communications/messages/send { contactId, body }
//   POST /communications/messages/mark-read { contactId }
import SwiftUI

struct MessageConversation: Identifiable, Decodable {
    let threadKey: String?
    let contactId: String?
    let displayName: String?
    let phone: String?
    let email: String?
    let lastAt: String?
    let lastBody: String?
    let unreadCount: Int?

    enum CodingKeys: String, CodingKey {
        case threadKey = "thread_key"
        case contactId = "contact_id"
        case displayName = "display_name"
        case phone, email
        case lastAt = "last_at"
        case lastBody = "last_body"
        case unreadCount = "unread_count"
    }

    // BOREAL_DIALER_DECODE_AND_ACCENT_v36 - counts arrive as 2 or "2".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threadKey = try c.decodeIfPresent(String.self, forKey: .threadKey)
        contactId = try c.decodeIfPresent(String.self, forKey: .contactId)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        lastAt = try c.decodeIfPresent(String.self, forKey: .lastAt)
        lastBody = try c.decodeIfPresent(String.self, forKey: .lastBody)
        unreadCount = FlexibleInt.decode(c, forKey: .unreadCount)
    }

    var id: String { contactId ?? threadKey ?? UUID().uuidString }
    var unread: Int { unreadCount ?? 0 }

    var title: String {
        if let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let phone, !phone.isEmpty { return PhoneFormat.display(phone) }
        return email ?? "Unknown contact"
    }
}

// BOREAL_DIALER_v820_WATCH - lets a tapped client-message / handoff alert open the conversation by contact id.
extension MessageConversation {
    init(contactId: String, displayName: String?) {
        self.threadKey = nil
        self.contactId = contactId
        self.displayName = displayName
        self.phone = nil
        self.email = nil
        self.lastAt = nil
        self.lastBody = nil
        self.unreadCount = nil
    }
}

private struct MessageConversationsEnvelope: Decodable {
    let conversations: [MessageConversation]
}

struct ThreadMessage: Identifiable, Decodable {
    let id: String
    let body: String?
    let senderType: String?
    let senderName: String?
    let createdAt: String?
    // BOREAL_DIALER_BLOCK_v510_MESSAGES_READ_RECEIPTS - when the client opened a staff message.
    let readAt: String?

    var readLabel: String {
        guard let readAt, let date = CalendarFormatters.parse(readAt) else { return "Delivered" }
        return "Read " + CalendarFormatters.time.string(from: date)
    }

    var isOutbound: Bool { (senderType ?? "").lowercased() == "staff" }

    var timeLabel: String {
        guard let date = CalendarFormatters.parse(createdAt) else { return "" }
        return CalendarFormatters.time.string(from: date)
    }
}

// BOREAL_DIALER_v817_MESSAGING - one search field for SMS, Messages and Team.
struct ListSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(Theme.muted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }
}

@MainActor
final class MessagesViewModel: ObservableObject {
    @Published var conversations: [MessageConversation] = []
    @Published var loading = false
    @Published var error: String?
    @Published var query = ""

    private var searchTask: Task<Void, Never>?

    func load() async {
        loading = true
        error = nil
        do {
            var path = "/communications/messages-list"
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                path += "?q=\(encoded)"
            }
            let request = try APIClient.shared.makeRequest(path: path)
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            conversations = try JSONDecoder().decode(MessageConversationsEnvelope.self, from: data)
                .conversations
                .filter { !($0.contactId ?? "").isEmpty }
            if trimmed.isEmpty { InboxUnreadStore.shared.update(from: conversations) }
        } catch {
            self.error = "Could not load messages."
        }
        loading = false
    }

    func queryChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }
}

// BOREAL_DIALER_v803_UI - whether any Messages conversation is unread, for the
// green dot on the Messages pill in the tab rail.
@MainActor
final class InboxUnreadStore: ObservableObject {
    static let shared = InboxUnreadStore()
    @Published private(set) var hasUnread = false

    private init() {}

    func update(from conversations: [MessageConversation]) {
        hasUnread = conversations.contains { $0.unread > 0 }
    }

    func refresh() async {
        do {
            let request = try APIClient.shared.makeRequest(path: "/communications/messages-list")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            update(from: try JSONDecoder().decode(MessageConversationsEnvelope.self, from: data).conversations)
        } catch {
            // Decoration only; keep the last known state.
        }
    }
}

struct MessagesView: View {
    @StateObject private var viewModel = MessagesViewModel()
    // BOREAL_DIALER_MAYA_SESSIONS_v789 - Maya's live chats, read-only.
    @State private var showMaya = false
    // BOREAL_DIALER_v820_WATCH - the conversation a tapped client-message / handoff alert opens.
    @State private var alertConversation: MessageConversation?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ViewHeader(title: "Messages", subtitle: "Client portal chats") {
                    Button {
                        showMaya = true
                    } label: {
                        HeaderActionLabel(text: "Maya chats")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Maya live chats")
                }

                ListSearchField(placeholder: "Search by name, phone or email", text: $viewModel.query)
                    .onChange(of: viewModel.query) { _ in viewModel.queryChanged() }

                content
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showMaya) {
                MayaSessionsView()
            }
            // BOREAL_DIALER_v820_WATCH
            .navigationDestination(isPresented: Binding(
                get: { alertConversation != nil },
                set: { if !$0 { alertConversation = nil } }
            )) {
                if let conversation = alertConversation {
                    MessageThreadView(conversation: conversation) {
                        Task { await viewModel.load() }
                    }
                }
            }
        }
        .task { await viewModel.load() }
        // BOREAL_DIALER_v820_WATCH - a client-message / handoff alert opens that contact's conversation (or just this tab).
        .onReceive(AlertNavigator.shared.$pending) { destination in
            guard let destination else { return }
            switch destination {
            case .messagesConversation(let contactId):
                alertConversation = viewModel.conversations.first { $0.contactId == contactId }
                    ?? MessageConversation(contactId: contactId, displayName: nil)
                AlertNavigator.shared.finish(destination)
            case .messages:
                AlertNavigator.shared.finish(destination)
            default:
                return
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.loading && viewModel.conversations.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.conversations.isEmpty {
            Text(viewModel.error ?? (viewModel.query.isEmpty ? "No conversations" : "No matches"))
                .font(.system(size: 14))
                .foregroundColor(Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(viewModel.conversations) { conversation in
                NavigationLink {
                    MessageThreadView(conversation: conversation) {
                        Task { await viewModel.load() }
                    }
                } label: {
                    MessageConversationRow(conversation: conversation)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .refreshable { await viewModel.load() }
        }
    }
}

// BOREAL_DIALER_v803_UI - 46pt avatar, name, one muted preview line, time over
// a green unread badge.
private struct MessageConversationRow: View {
    let conversation: MessageConversation

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            AvatarCircle(name: conversation.title, size: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title).rowTitle().lineLimit(1)
                Text((conversation.lastBody ?? "").ifEmpty(" "))
                    .rowSubtitle()
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                Text(RowTime.label(conversation.lastAt))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.faint)
                CountBadge(count: conversation.unread)
                    .opacity(conversation.unread > 0 ? 1 : 0)
            }
        }
        .padding(.vertical, 11)
    }
}

struct MessageThreadView: View {
    // BOREAL_DIALER_THREAD_SCROLL_v166
    // BOREAL_DIALER_SCROLL_BOTTOM_v649 - jump to a fixed marker after the last message, and try
    // again as rows finish laying out (one early jump often stopped part-way).
    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !messages.isEmpty else { return }
        for delay in [0.0, 0.15, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if animated && delay == 0 {
                    withAnimation { proxy.scrollTo(ThreadBottom.id, anchor: .bottom) }
                } else {
                    proxy.scrollTo(ThreadBottom.id, anchor: .bottom)
                }
            }
        }
    }

    let conversation: MessageConversation
    var onChange: () -> Void

    @State private var messages: [ThreadMessage] = []
    @State private var draft = ""
    // BOREAL_DIALER_TEMPLATES_EVERYWHERE_v167
    @State private var showingTemplates = false
    @State private var sending = false
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            if loading && messages.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if messages.isEmpty {
                Text(error ?? "No messages in this conversation.")
                    .foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(messages) { message in
                                ThreadBubble(message: message).id(message.id)
                            }
                            ThreadBottom()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    .onAppear { scrollToLatest(proxy, animated: false) }
                    .onChange(of: messages.count) { _ in
                        scrollToLatest(proxy, animated: true)
                    }
                    .onChange(of: messages.last?.id) { _ in scrollToLatest(proxy, animated: true) }
                }
            }

            if let error, !messages.isEmpty {
                Text(error).font(.footnote).foregroundColor(Theme.red).padding(.horizontal)
            }

            ComposerBar(
                placeholder: "Reply…",
                text: $draft,
                disabled: sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onTemplates: { showingTemplates = true },
                onSend: send
            )
            .sheet(isPresented: $showingTemplates) {
                TemplatePickerSheet(
                    channel: "sms",
                    isPresented: $showingTemplates,
                    text: $draft
                )
            }
        }
        .background(Theme.bg)
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            await loadMessages()
            await markRead()
        }
    }

    private var contactId: String { conversation.contactId ?? "" }

    private func loadMessages() async {
        guard !contactId.isEmpty,
              let encoded = contactId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            loading = false
            return
        }
        loading = true
        do {
            let request = try APIClient.shared.makeRequest(
                path: "/communications/messages/thread?contactId=\(encoded)"
            )
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            messages = try JSONDecoder().decode([ThreadMessage].self, from: data)
            error = nil
        } catch {
            self.error = "Could not load this conversation."
        }
        loading = false
    }

    // Clears the unread badge. Best effort: a failed mark-read must not look
    // like the conversation failed to open.
    private func markRead() async {
        guard conversation.unread > 0, !contactId.isEmpty,
              let body = try? JSONSerialization.data(withJSONObject: ["contactId": contactId]),
              let request = try? APIClient.shared.makeRequest(
                  path: "/communications/messages/mark-read",
                  method: "POST",
                  body: body
              ) else { return }
        _ = try? await APIClient.shared.makeAuthorizedRequest(request)
        onChange()
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !contactId.isEmpty else { return }
        sending = true
        error = nil
        Task {
            do {
                let payload = try JSONSerialization.data(withJSONObject: ["contactId": contactId, "body": text])
                let request = try APIClient.shared.makeRequest(
                    path: "/communications/messages/send",
                    method: "POST",
                    body: payload
                )
                _ = try await APIClient.shared.makeAuthorizedRequest(request)
                draft = ""
                await loadMessages()
                onChange()
            } catch {
                self.error = "Couldn't send that reply. Please try again."
            }
            sending = false
        }
    }
}

private struct ThreadBubble: View {
    let message: ThreadMessage

    var body: some View {
        HStack {
            if message.isOutbound { Spacer(minLength: 40) }

            // BOREAL_DIALER_THREAD_STYLE_v32
            VStack(alignment: message.isOutbound ? .trailing : .leading, spacing: 4) {
                ChatBubble(outbound: message.isOutbound) {
                    Text(message.body ?? "")
                }
                Text(message.timeLabel)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.faint)
                // BOREAL_DIALER_BLOCK_v510_MESSAGES_READ_RECEIPTS
                if message.isOutbound {
                    Text(message.readLabel)
                        .font(.system(size: 12))
                        .foregroundColor(message.readAt == nil ? Theme.faint : Theme.green)
                }
            }

            if !message.isOutbound { Spacer(minLength: 40) }
        }
    }
}

// BOREAL_DIALER_SCROLL_BOTTOM_v649
// An invisible marker placed after the last message in every conversation (SMS, Messages, Team).
// Screens scroll to it so the newest message is always in view.
struct ThreadBottom: View {
    static let id = "boreal-thread-bottom"
    var body: some View {
        Color.clear.frame(height: 1).id(ThreadBottom.id)
    }
}
