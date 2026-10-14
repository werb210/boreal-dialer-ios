// BOREAL_DIALER_MESSAGES_THREAD_v10
// The Messages tab is the CMP chat and "talk to a human" escalation inbox - the
// conversations a client starts on the website or the client portal that a
// staff member has to pick up. SMS has its own tab, so SMS threads are filtered
// out here rather than duplicated.
//
//   GET  /communications/threads          -> [ ...conversations ]
//   GET  /communications/threads/:id      -> { ..., messages: [...] }
//   POST /communications/threads/:id/messages { body } -> staff reply
//
// The list endpoint returns messages: [] on purpose and defers history to the
// detail call, so opening a thread always fetches.
import SwiftUI

struct CommunicationThread: Identifiable, Decodable {
    let id: String
    let sessionId: String?
    let type: String?
    let silo: String?
    let contactId: String?
    let contactName: String?
    let contactPhone: String?
    let contactEmail: String?
    let unread: Int?
    let message: String?
    let updatedAt: String?

    // BOREAL_DIALER_DECODE_AND_ACCENT_v36 - same bigint-as-string trap.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        silo = try c.decodeIfPresent(String.self, forKey: .silo)
        contactId = try c.decodeIfPresent(String.self, forKey: .contactId)
        contactName = try c.decodeIfPresent(String.self, forKey: .contactName)
        contactPhone = try c.decodeIfPresent(String.self, forKey: .contactPhone)
        contactEmail = try c.decodeIfPresent(String.self, forKey: .contactEmail)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        unread = FlexibleInt.decode(c, forKey: .unread)
    }

    enum CodingKeys: String, CodingKey {
        case id, type, silo, unread, message
        case sessionId, contactId, contactName, contactPhone, contactEmail
        case updatedAt
    }

    var isSMS: Bool { (type ?? "").lowercased() == "sms" }

    // BOREAL_DIALER_v803_UI - the mockup's three channels. A website / Maya chat
    // and a chat a staff member has picked up ("human") are both Chat.
    var channelLabel: String {
        switch (type ?? "").lowercased() {
        case "sms": return "SMS"
        case "email", "mail": return "Email"
        default: return "Chat"
        }
    }

    // BOREAL_DIALER_v803_UI - an SMS row opens the SMS conversation, which is
    // the screen that actually sends a text.
    var asSMSThread: SMSThread {
        SMSThread(contactId: contactId, displayName: contactName, phone: contactPhone, unreadCount: unread)
    }

    var title: String {
        contactName ?? contactPhone ?? contactEmail ?? "Unknown contact"
    }
}

struct ThreadMessage: Identifiable, Decodable {
    let id: String
    let type: String?
    let direction: String?
    let message: String?
    let createdAt: String?
    // BOREAL_DIALER_BLOCK_v510_MESSAGES_READ_RECEIPTS - BF-Server v507 returns when
    // the client opened a staff message (portal v508 shows the same).
    let readAt: String?

    var readLabel: String {
        guard let readAt, let date = CalendarFormatters.parse(readAt) else { return "Delivered" }
        return "Read " + CalendarFormatters.time.string(from: date)
    }

    // "in" from the client, "out" from staff, "system" for anything generated.
    var isOutbound: Bool { (direction ?? "") == "out" }
    var isSystem: Bool { (direction ?? "") == "system" }

    var timeLabel: String {
        guard let date = CalendarFormatters.parse(createdAt) else { return "" }
        return CalendarFormatters.time.string(from: date)
    }
}

private struct ThreadDetail: Decodable {
    let id: String
    let contactName: String?
    let messages: [ThreadMessage]
}

@MainActor
final class MessagesViewModel: ObservableObject {
    @Published var threads: [CommunicationThread] = []
    @Published var loading = false
    @Published var error: String?
    // BOREAL_DIALER_TABS_PRESENTATION_v26
    @Published var filter: Filter = .all

    // BOREAL_DIALER_v803_UI - All, Unread, SMS, Chat, Email (the mockup's filters).
    enum Filter: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
        case sms = "SMS"
        case chat = "Chat"
        case email = "Email"
    }

    var unreadCount: Int {
        threads.reduce(0) { $0 + ($1.unread ?? 0) }
    }

    var visible: [CommunicationThread] {
        switch filter {
        case .all: return threads
        case .unread: return threads.filter { ($0.unread ?? 0) > 0 }
        case .sms: return threads.filter { $0.channelLabel == "SMS" }
        case .chat: return threads.filter { $0.channelLabel == "Chat" }
        case .email: return threads.filter { $0.channelLabel == "Email" }
        }
    }

    func load() async {
        loading = true
        error = nil
        do {
            let request = try APIClient.shared.makeRequest(path: "/communications/threads")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            // BOREAL_DIALER_v803_UI - the unified inbox shows every channel; SMS
            // rows open the SMS conversation rather than this thread view.
            threads = try JSONDecoder().decode([CommunicationThread].self, from: data)
            InboxUnreadStore.shared.update(from: threads)
        } catch {
            self.error = "Could not load messages."
        }
        loading = false
    }
}

// BOREAL_DIALER_v803_UI - whether any inbox conversation is unread, for the
// green dot on the Messages pill in the tab rail.
@MainActor
final class InboxUnreadStore: ObservableObject {
    static let shared = InboxUnreadStore()
    @Published private(set) var hasUnread = false

    private init() {}

    func update(from threads: [CommunicationThread]) {
        hasUnread = threads.contains { ($0.unread ?? 0) > 0 }
    }

    func refresh() async {
        do {
            let request = try APIClient.shared.makeRequest(path: "/communications/threads")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            update(from: try JSONDecoder().decode([CommunicationThread].self, from: data))
        } catch {
            // Decoration only; keep the last known state.
        }
    }
}

struct MessagesView: View {
    @StateObject private var viewModel = MessagesViewModel()
    // BOREAL_DIALER_v803_UI - the Compose menu replaces the unlabelled sparkle
    // button: a new text message, and Maya's live chats (still read-only).
    @State private var showNewMessage = false
    @State private var showMaya = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // BOREAL_DIALER_v803_UI - mockup header.
                ViewHeader(title: "Messages", subtitle: "Unified inbox \u{00B7} all channels") {
                    Menu {
                        Button {
                            showNewMessage = true
                        } label: {
                            Label("New text message", systemImage: "square.and.pencil")
                        }
                        // BOREAL_DIALER_MAYA_SESSIONS_v789 - Maya's live chats, read-only.
                        Button {
                            showMaya = true
                        } label: {
                            Label("Maya live chats", systemImage: "sparkles")
                        }
                    } label: {
                        HeaderActionLabel(text: "Compose")
                    }
                    .accessibilityLabel("Compose")
                }

                // BOREAL_DIALER_TABS_PRESENTATION_v26 - filter chips.
                // BOREAL_DIALER_v803_UI - All, Unread . N, SMS, Chat, Email.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MessagesViewModel.Filter.allCases, id: \.self) { option in
                            FilterChip(
                                title: chipTitle(option),
                                selected: viewModel.filter == option
                            ) {
                                viewModel.filter = option
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                }

                content
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showMaya) {
                MayaSessionsView()
            }
            .sheet(isPresented: $showNewMessage) {
                SMSNewMessageView {
                    Task { await viewModel.load() }
                }
            }
        }
        .task { await viewModel.load() }
    }

    private func chipTitle(_ option: MessagesViewModel.Filter) -> String {
        if option == .unread && viewModel.unreadCount > 0 {
            return "Unread \u{00B7} \(viewModel.unreadCount)"
        }
        return option.rawValue
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.loading && viewModel.threads.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.visible.isEmpty {
            Text(viewModel.error ?? (viewModel.threads.isEmpty ? "No conversations" : "Nothing in this filter"))
                .font(.system(size: 14))
                .foregroundColor(Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(viewModel.visible) { thread in
                NavigationLink {
                    destination(for: thread)
                } label: {
                    MessageThreadRow(thread: thread)
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

    @ViewBuilder
    private func destination(for thread: CommunicationThread) -> some View {
        if thread.isSMS {
            SMSThreadView(thread: thread.asSMSThread) {
                Task { await viewModel.load() }
            }
        } else {
            MessageThreadView(thread: thread) {
                Task { await viewModel.load() }
            }
        }
    }
}

// BOREAL_DIALER_v803_UI - mockup row: 46pt avatar, 15.5pt name with a channel
// chip, one muted preview line, time over a green unread badge.
private struct MessageThreadRow: View {
    let thread: CommunicationThread

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            AvatarCircle(name: thread.title, size: 46)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(thread.title).rowTitle().lineLimit(1)
                    ChannelChip(label: thread.channelLabel)
                }
                Text((thread.message ?? "").ifEmpty(" "))
                    .rowSubtitle()
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                Text(RowTime.label(thread.updatedAt))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.faint)
                CountBadge(count: thread.unread ?? 0)
                    .opacity((thread.unread ?? 0) > 0 ? 1 : 0)
            }
        }
        .padding(.vertical, 11)
    }
}

struct MessageThreadView: View {
    // BOREAL_DIALER_THREAD_SCROLL_v166
    // BOREAL_DIALER_SCROLL_BOTTOM_v649 - jump to a fixed marker after the last message, and try
    // again as rows and pictures finish laying out (one early jump often stopped part-way).
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

    let thread: CommunicationThread
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
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 8) { // BOREAL_DIALER_SCROLL_BOTTOM_v649 - all rows exist, so the jump lands
                            ForEach(messages) { message in
                                ThreadBubble(message: message).id(message.id)
                            }
                            ThreadBottom()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    // BOREAL_DIALER_THREAD_SCROLL_v166
                    // onAppear covers the first render; onChange covers new
                    // messages arriving afterwards.
                    .onAppear { scrollToLatest(proxy, animated: false) }
                    .onChange(of: messages.count) { _ in
                        scrollToLatest(proxy, animated: true)
                    }
                    .onChange(of: messages.last?.id) { _ in scrollToLatest(proxy, animated: true) }
                }
            }

            if let error, !messages.isEmpty {
                Text(error).font(.footnote).foregroundColor(.red).padding(.horizontal)
            }

            // BOREAL_DIALER_TEMPLATES_EVERYWHERE_v167 - supplying onTemplates
            // is what makes ComposerBar render the templates button; without it
            // the button is simply absent, which is why this thread had none.
            ComposerBar(
                placeholder: "Reply…",
                text: $draft,
                disabled: sending || draft.trimmingCharacters(in: .whitespaces).isEmpty,
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
        .navigationTitle(thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMessages() }
    }

    private func loadMessages() async {
        loading = true
        do {
            let request = try APIClient.shared.makeRequest(
                path: "/communications/threads/\(thread.id)"
            )
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            messages = try JSONDecoder().decode(ThreadDetail.self, from: data).messages
            error = nil
        } catch {
            self.error = "Could not load this conversation."
        }
        loading = false
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        sending = true
        error = nil
        Task {
            do {
                let payload = try JSONSerialization.data(withJSONObject: ["body": text])
                let request = try APIClient.shared.makeRequest(
                    path: "/communications/threads/\(thread.id)/messages",
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
        if message.isSystem {
            Text(message.message ?? "")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            HStack {
                if message.isOutbound { Spacer(minLength: 40) }

                // BOREAL_DIALER_THREAD_STYLE_v32
                VStack(alignment: message.isOutbound ? .trailing : .leading, spacing: 4) {
                    ChatBubble(outbound: message.isOutbound) {
                        Text(message.message ?? "")
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
