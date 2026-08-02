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
                    List(viewModel.threads) { thread in
                        NavigationLink {
                            MessageThreadView(thread: thread) {
                                Task { await viewModel.load() }
                            }
                        } label: {
                            MessageThreadRow(thread: thread)
                        }
                    }
                    .listStyle(.plain)
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
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(thread.title).font(.body.weight(.semibold))
                    Text(thread.channelLabel)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                if let preview = thread.message, !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let unread = thread.unread, unread > 0 {
                Text("\(unread)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Circle().fill(Color.accentColor))
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

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Reply", text: $draft, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(sending || draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
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

                VStack(alignment: message.isOutbound ? .trailing : .leading, spacing: 4) {
                    Text(message.message ?? "")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(message.isOutbound ? Color.accentColor : Color.secondary.opacity(0.18))
                        .foregroundColor(message.isOutbound ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    Text(message.timeLabel).font(.caption2).foregroundColor(.secondary)
                }

                if !message.isOutbound { Spacer(minLength: 40) }
            }
        }
    }
}
