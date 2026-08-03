// BOREAL_DIALER_SMS_THREADS_v9
// The BF silo SMS tab, matching the portal: a thread list keyed by contact,
// tapping through to the conversation, sending replies, and MMS media.
//
// It previously called /communications/messages-list, which deliberately
// EXCLUDES SMS - the type filter there is `m.type <> 'sms'` unless ?types= is
// passed - so the tab was always empty. The SMS endpoints are:
//   GET  /communications/sms                -> { conversations: [...] }
//   GET  /communications/sms/thread         -> { messages: [...] }
//   POST /communications/sms                -> send one message
//   POST /communications/messages/mark-read -> clear the unread badge
import SwiftUI

struct SMSThread: Identifiable, Decodable {
    let threadKey: String?
    let contactId: String?
    let displayName: String?
    let phone: String?
    let lastAt: String?
    let lastBody: String?
    let unreadCount: Int?

    enum CodingKeys: String, CodingKey {
        case threadKey = "thread_key"
        case contactId = "contact_id"
        case displayName = "display_name"
        case phone
        case lastAt = "last_at"
        case lastBody = "last_body"
        case unreadCount = "unread_count"
    }

    var id: String { threadKey ?? contactId ?? phone ?? UUID().uuidString }
    var title: String { displayName ?? phone ?? "Unknown" }
    var unread: Int { unreadCount ?? 0 }
}

struct SMSMessage: Identifiable, Decodable {
    let id: String
    let contactId: String?
    let fromNumber: String?
    let toNumber: String?
    let direction: String?
    let body: String?
    let mediaUrl: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, direction, body
        case contactId = "contact_id"
        case fromNumber = "from_number"
        case toNumber = "to_number"
        case mediaUrl = "media_url"
        case createdAt = "created_at"
    }

    var isOutbound: Bool { (direction ?? "").lowercased() == "outbound" }
    var hasMedia: Bool { !(mediaUrl ?? "").isEmpty }

    var timeLabel: String {
        guard let date = CalendarFormatters.parse(createdAt) else { return "" }
        return CalendarFormatters.time.string(from: date)
    }
}

private struct ThreadsEnvelope: Decodable { let conversations: [SMSThread] }
private struct MessagesEnvelope: Decodable { let messages: [SMSMessage] }

@MainActor
final class SMSViewModel: ObservableObject {
    @Published var threads: [SMSThread] = []
    @Published var loading = false
    @Published var error: String?

    func load() async {
        loading = true
        error = nil
        do {
            let request = try APIClient.shared.makeRequest(path: "/communications/sms")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            threads = try JSONDecoder().decode(ThreadsEnvelope.self, from: data).conversations
        } catch {
            self.error = "Could not load messages."
        }
        loading = false
    }
}

struct SMSView: View {
    @StateObject private var viewModel = SMSViewModel()
    // BOREAL_DIALER_SMS_BROADCAST_v20
    @State private var showBroadcast = false

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
                            SMSThreadView(thread: thread) {
                                Task { await viewModel.load() }
                            }
                        } label: {
                            SMSThreadRow(thread: thread)
                        }
                    }
                    .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
                    .refreshable { await viewModel.load() }
                }
            }
            .navigationTitle("SMS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showBroadcast = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showBroadcast) {
                SMSBroadcastView()
            }
        }
        .task { await viewModel.load() }
    }
}

private struct SMSThreadRow: View {
    let thread: SMSThread

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(thread.title)
                    .font(.body.weight(thread.unread > 0 ? .semibold : .regular))
                if let preview = thread.lastBody, !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if thread.unread > 0 {
                Text("\(thread.unread)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Circle().fill(Color.accentColor))
            }
        }
        .padding(.vertical, 4)
    }
}

struct SMSThreadView: View {
    let thread: SMSThread
    var onChange: () -> Void

    @State private var messages: [SMSMessage] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            if loading && messages.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(messages) { message in
                                SMSBubble(message: message).id(message.id)
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

            if let error {
                Text(error).font(.footnote).foregroundColor(.red).padding(.horizontal)
            }

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                // Two to three lines tall, per the portal's compose fix.
                TextField("Message", text: $draft, axis: .vertical)
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
        .task {
            await loadMessages()
            await markRead()
        }
    }

    private var threadQuery: String? {
        if let contactId = thread.contactId, !contactId.isEmpty {
            return "contactId=\(contactId)"
        }
        if let phone = thread.phone,
           let encoded = phone.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return "phone=\(encoded)"
        }
        return nil
    }

    private func loadMessages() async {
        guard let query = threadQuery else { loading = false; return }
        loading = true
        do {
            let request = try APIClient.shared.makeRequest(path: "/communications/sms/thread?\(query)")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            messages = try JSONDecoder().decode(MessagesEnvelope.self, from: data).messages
        } catch {
            self.error = "Could not load this conversation."
        }
        loading = false
    }

    // Clears the unread badge for this thread. Best effort: failing to mark read
    // should not look like the conversation failed to open.
    private func markRead() async {
        guard thread.unread > 0 else { return }
        var payload: [String: String] = [:]
        if let contactId = thread.contactId, !contactId.isEmpty {
            payload["contactId"] = contactId
        } else if let phone = thread.phone {
            payload["phone"] = phone
        } else {
            return
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let request = try? APIClient.shared.makeRequest(
            path: "/communications/messages/mark-read",
            method: "POST",
            body: body
        )
        guard let request else { return }
        _ = try? await APIClient.shared.makeAuthorizedRequest(request)
        onChange()
    }

    private func send() {
        guard let to = thread.phone, !to.isEmpty else {
            error = "This conversation has no phone number to reply to."
            return
        }
        let text = draft
        sending = true
        error = nil
        Task {
            do {
                try await API.sendSMS(
                    SendSMSPayload(to: to, body: text, contactId: thread.contactId)
                )
                draft = ""
                await loadMessages()
                onChange()
            } catch {
                self.error = "Couldn't send that message. Please try again."
            }
            sending = false
        }
    }
}

private struct SMSBubble: View {
    let message: SMSMessage

    var body: some View {
        HStack {
            if message.isOutbound { Spacer(minLength: 40) }

            VStack(alignment: message.isOutbound ? .trailing : .leading, spacing: 4) {
                if message.hasMedia, let url = mediaURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit().frame(maxWidth: 220)
                        case .failure:
                            Label("Attachment unavailable", systemImage: "photo")
                                .font(.caption).foregroundColor(.secondary)
                        default:
                            ProgressView().frame(width: 120, height: 90)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if let body = message.body, !body.isEmpty {
                    Text(body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(message.isOutbound ? Color.accentColor : Color.secondary.opacity(0.18))
                        .foregroundColor(message.isOutbound ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Text(message.timeLabel).font(.caption2).foregroundColor(.secondary)
            }

            if !message.isOutbound { Spacer(minLength: 40) }
        }
    }
}

private extension SMSBubble {
    // Twilio media needs Basic auth, so it is proxied by the server. The token
    // rides the query string because AsyncImage cannot set a header.
    var mediaURL: URL? {
        guard message.hasMedia, let token = TokenStorage.shared.getToken() else { return nil }
        let base = APIConfig.baseURL
        return URL(string: "\(base)/communications/messages/\(message.id)/media?token=\(token)")
    }
}
