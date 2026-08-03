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

    var isSMS: Bool { (type ?? "").lowercased() == "sms" }

    var channelLabel: String {
        switch (type ?? "").lowercased() {
        case "human": return "Human"
        case "chat": return "Chat"
        case "sms": return "SMS"
        default: return "Message"
        }
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

    enum Filter: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
        case chat = "Chat"
        case human = "Human"
    }

    var unreadCount: Int {
        threads.reduce(0) { $0 + ($1.unread ?? 0) }
    }

    var visible: [CommunicationThread] {
        switch filter {
        case .all: return threads
        case .unread: return threads.filter { ($0.unread ?? 0) > 0 }
        case .chat: return threads.filter { $0.channelLabel == "Chat" }
        case .human: return threads.filter { $0.channelLabel == "Human" }
        }
    }

    func load() async {
        loading = true
        error = nil
        do {
            let request = try APIClient.shared.makeRequest(path: "/communications/threads")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            let all = try JSONDecoder().decode([CommunicationThread].self, from: data)
            // SMS lives in its own tab.
            threads = all.filter { !$0.isSMS }
        } catch {
            self.error = "Could not load messages."
        }
        loading = false
    }
}

struct MessagesView: View {
    @StateObject private var viewModel = MessagesViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.loading && viewModel.threads.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.threads.isEmpty {
                    Text(viewModel.error ?? "No conversations")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // BOREAL_DIALER_TABS_PRESENTATION_v26 - filter chips.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(MessagesViewModel.Filter.allCases, id: \.self) { option in
                                let selected = viewModel.filter == option
                                let title = option == .unread && viewModel.unreadCount > 0
                                    ? "Unread · \(viewModel.unreadCount)"
                                    : option.rawValue
                                Button {
                                    viewModel.filter = option
                                } label: {
                                    Text(title)
                                        .font(.caption.weight(selected ? .semibold : .regular))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule().fill(selected
                                                ? Color.accentColor.opacity(0.18)
                                                : Color.secondary.opacity(0.12))
                                        )
                                        .foregroundColor(selected ? .accentColor : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                    }

                    List(viewModel.visible) { thread in
                        NavigationLink {
                            MessageThreadView(thread: thread) {
                                Task { await viewModel.load() }
                            }
                        } label: {
                            MessageThreadRow(thread: thread)
                        }
                    }
                    .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
                    .refreshable { await viewModel.load() }
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await viewModel.load() }
    }
}

private struct MessageThreadRow: View {
    let thread: CommunicationThread

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarCircle(name: thread.title, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(thread.title).rowTitle()
                    ChannelChip(label: thread.channelLabel)
                }
                if let preview = thread.message, !preview.isEmpty {
                    Text(preview).rowSubtitle().lineLimit(1)
                }
            }
            Spacer()
            if let unread = thread.unread, unread > 0 {
                CountBadge(count: unread)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MessageThreadView: View {
    let thread: CommunicationThread
    var onChange: () -> Void

    @State private var messages: [ThreadMessage] = []
    @State private var draft = ""
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
                        LazyVStack(spacing: 8) {
                            ForEach(messages) { message in
                                ThreadBubble(message: message).id(message.id)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }

            if let error, !messages.isEmpty {
                Text(error).font(.footnote).foregroundColor(.red).padding(.horizontal)
            }

            ComposerBar(
                placeholder: "Reply…",
                text: $draft,
                disabled: sending || draft.trimmingCharacters(in: .whitespaces).isEmpty,
                onSend: send
            )
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
                }

                if !message.isOutbound { Spacer(minLength: 40) }
            }
        }
    }
}
