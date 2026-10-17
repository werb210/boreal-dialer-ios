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
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct SMSThread: Identifiable, Decodable {
    let threadKey: String?
    let contactId: String?
    let displayName: String?
    let phone: String?
    let lastAt: String?
    let lastBody: String?
    let unreadCount: Int?

    // BOREAL_DIALER_DECODE_AND_ACCENT_v36 - accepts 2 or "2".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threadKey = try c.decodeIfPresent(String.self, forKey: .threadKey)
        contactId = try c.decodeIfPresent(String.self, forKey: .contactId)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        lastAt = try c.decodeIfPresent(String.self, forKey: .lastAt)
        lastBody = try c.decodeIfPresent(String.self, forKey: .lastBody)
        unreadCount = FlexibleInt.decode(c, forKey: .unreadCount)
    }

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
    var title: String {
        // BOREAL_DIALER_v817_MESSAGING - a contact named by its number shows formatted.
        if let displayName, !displayName.isEmpty {
            return displayName.hasPrefix("+") ? PhoneFormat.display(displayName) : displayName
        }
        return phone.map { PhoneFormat.display($0) } ?? "Unknown"
    }
    var unread: Int { unreadCount ?? 0 }
}

// BOREAL_DIALER_v803_UI - lets the unified Messages inbox open an SMS row in
// the SMS conversation screen.
extension SMSThread {
    init(contactId: String?, displayName: String?, phone: String?, unreadCount: Int?) {
        self.threadKey = nil
        self.contactId = contactId
        self.displayName = displayName
        self.phone = phone
        self.lastAt = nil
        self.lastBody = nil
        self.unreadCount = unreadCount
    }
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
    // BOREAL_DIALER_BLOCK_v501_SMS_PARITY - BF-Server v499 delivery result
    let deliveryStatus: String?
    let deliveryError: String?

    enum CodingKeys: String, CodingKey {
        case id, direction, body
        case contactId = "contact_id"
        case fromNumber = "from_number"
        case toNumber = "to_number"
        case mediaUrl = "media_url"
        case createdAt = "created_at"
        case deliveryStatus = "delivery_status"
        case deliveryError = "delivery_error"
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
    // BOREAL_DIALER_v817_MESSAGING - search by name or number (BF-Server ?q=).
    @Published var query = ""
    private var searchTask: Task<Void, Never>?

    func queryChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    func load() async {
        loading = true
        error = nil
        do {
            var path = "/communications/sms"
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                path += "?q=\(encoded)"
            }
            let request = try APIClient.shared.makeRequest(path: path)
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
    // BOREAL_DIALER_SMS_NEW_MESSAGE_v33
    @State private var showNewMessage = false
    // BOREAL_DIALER_v820_WATCH - the thread a tapped SMS / handoff alert opens.
    @State private var alertThread: SMSThread?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // BOREAL_DIALER_v803_UI - mockup view header with a green Compose action.
                ViewHeader(title: "SMS", subtitle: "Text conversations") {
                    // BOREAL_DIALER_SMS_NEW_MESSAGE_v33
                    Menu {
                        Button {
                            showNewMessage = true
                        } label: {
                            Label("New message", systemImage: "square.and.pencil")
                        }
                        Button {
                            showBroadcast = true
                        } label: {
                            Label("Broadcast", systemImage: "person.2.fill")
                        }
                    } label: {
                        HeaderActionLabel(text: "Compose")
                    }
                    .accessibilityLabel("Compose")
                }

                // BOREAL_DIALER_v817_MESSAGING
                ListSearchField(placeholder: "Search by name or number", text: $viewModel.query)
                    .onChange(of: viewModel.query) { _ in viewModel.queryChanged() }

                if viewModel.loading && viewModel.threads.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.threads.isEmpty {
                    Text(viewModel.error ?? (viewModel.query.isEmpty ? "No conversations" : "No matches"))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.muted)
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
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Theme.bg)
                    .refreshable { await viewModel.load() }
                }
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showBroadcast) {
                SMSBroadcastView()
            }
            .sheet(isPresented: $showNewMessage) {
                // Refresh on send so the new thread appears at the top.
                SMSNewMessageView {
                    Task { await viewModel.load() }
                }
            }
            // BOREAL_DIALER_v820_WATCH
            .navigationDestination(isPresented: Binding(
                get: { alertThread != nil },
                set: { if !$0 { alertThread = nil } }
            )) {
                if let thread = alertThread {
                    SMSThreadView(thread: thread) {
                        Task { await viewModel.load() }
                    }
                }
            }
        }
        .task { await viewModel.load() }
        // BOREAL_DIALER_v820_WATCH - an SMS (or SMS handoff) alert opens its thread. The list row, when loaded, supplies
        // the contact's name; otherwise the thread opens from the number / contact id alone.
        .onReceive(AlertNavigator.shared.$pending) { destination in
            guard let destination, case .smsThread(let phone, let contactId) = destination else { return }
            let known = viewModel.threads.first {
                (contactId != nil && $0.contactId == contactId) || (phone != nil && $0.phone == phone)
            }
            alertThread = known ?? SMSThread(contactId: contactId, displayName: nil, phone: phone, unreadCount: nil)
            AlertNavigator.shared.finish(destination)
        }
    }
}

private struct SMSThreadRow: View {
    let thread: SMSThread

    var body: some View {
        // BOREAL_DIALER_v803_UI - same row as the Messages inbox: 46pt avatar,
        // name + SMS chip, preview, time over the unread badge.
        HStack(alignment: .center, spacing: 13) {
            // BOREAL_DIALER_ROW_SEGMENT_STYLE_v31
            AvatarCircle(name: thread.title, size: 46)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(thread.title).rowTitle().lineLimit(1)
                    ChannelChip(label: "SMS")
                }
                Text((thread.lastBody ?? "").ifEmpty(" "))
                    .rowSubtitle()
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                Text(RowTime.label(thread.lastAt))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.faint)
                CountBadge(count: thread.unread)
                    .opacity(thread.unread > 0 ? 1 : 0)
            }
        }
        .padding(.vertical, 11)
    }
}

struct SMSThreadView: View {
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

    let thread: SMSThread
    var onChange: () -> Void

    @State private var messages: [SMSMessage] = []
    @State private var draft = ""
    // BOREAL_DIALER_TEMPLATES_EVERYWHERE_v167
    @State private var showingTemplates = false
    @State private var sending = false
    @State private var loading = true
    @State private var error: String?
    // BOREAL_DIALER_BLOCK_v501_SMS_PARITY - attach a picture or PDF
    @State private var media: SMSMediaPayload?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingPdfImporter = false
    @StateObject private var typing = SMSTypingMonitor() // BOREAL_DIALER_SMS_TYPING_v789

    private var draftIsEmpty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if loading && messages.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 8) { // BOREAL_DIALER_SCROLL_BOTTOM_v649 - all rows exist, so the jump lands
                            ForEach(messages) { message in
                                SMSBubble(message: message).id(message.id)
                            }
                            ThreadBottom()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    // BOREAL_DIALER_THREAD_SCROLL_v166 - same bug as
                    // MessagesView: onChange alone never fires for a thread
                    // that arrives fully populated.
                    .onAppear { scrollToLatest(proxy, animated: false) }
                    .onChange(of: messages.count) { _ in
                        scrollToLatest(proxy, animated: true)
                    }
                    .onChange(of: messages.last?.id) { _ in scrollToLatest(proxy, animated: true) }
                }
            }

            if let error {
                Text(error).font(.footnote).foregroundColor(.red).padding(.horizontal)
            }

            // BOREAL_DIALER_SMS_TYPING_v789
            if typing.clientTyping {
                Text("\(thread.title) is typing...")
                    .font(.caption)
                    .foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            // BOREAL_DIALER_TEMPLATES_EVERYWHERE_v167 - supplying onTemplates
            // is what makes ComposerBar render the templates button; without it
            // the button is simply absent, which is why this thread had none.
            // BOREAL_DIALER_BLOCK_v501_SMS_PARITY - attach + length/text counter (portal v498/v500)
            // BOREAL_DIALER_v803_UI - tidier attach row: two small outlined pills
            // (Photo, PDF), the attached file as a removable chip, the counter right.
            HStack(spacing: 8) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Photo", systemImage: "photo")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Theme.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(Capsule().stroke(Theme.line2, lineWidth: 1))
                }
                Button {
                    showingPdfImporter = true
                } label: {
                    Label("PDF", systemImage: "doc")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Theme.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(Capsule().stroke(Theme.line2, lineWidth: 1))
                }
                .buttonStyle(.plain)
                if let media {
                    HStack(spacing: 4) {
                        Text(media.name).lineLimit(1).foregroundColor(Theme.greenBright)
                        Button {
                            self.media = nil
                            photoItem = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(Theme.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove attachment")
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.surface2))
                }
                Spacer()
                if !draftIsEmpty {
                    Text(SmsSegments.label(draft))
                        .font(.system(size: 12))
                        .foregroundColor(SmsSegments.count(draft).segments > 1 ? .orange : Theme.faint)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .onChange(of: photoItem) { item in
                Task { await loadPhoto(item) }
            }
            .fileImporter(isPresented: $showingPdfImporter, allowedContentTypes: [UTType.pdf]) { result in
                loadPdf(result)
            }

            ComposerBar(
                placeholder: "Text message…",
                text: $draft,
                disabled: sending || (draftIsEmpty && media == nil),
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
        // BOREAL_DIALER_v803_UI - mockup thread header in the navigation bar (so
        // the system back chevron and swipe-back keep working): 38pt avatar, name,
        // number, and a round call button that dials this number.
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 11) {
                    AvatarCircle(name: thread.title, size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(thread.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                        Text(headerSubtitle)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.faint)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                RoundIconButton(systemImage: "phone.fill", accessibility: "Call \(thread.title)") {
                    if let phone = thread.phone, !phone.isEmpty {
                        CallManager.shared.startCall(to: phone)
                    }
                }
                .disabled((thread.phone ?? "").isEmpty)
            }
        }
        .task {
            await loadMessages()
            await markRead()
        }
        // BOREAL_DIALER_SMS_TYPING_v789 - staff typing goes out (throttled), the
        // client's typing is polled while the thread is open.
        .onChange(of: draft) { text in typing.userTyped(contactId: thread.contactId, draft: text) }
        .task(id: thread.contactId) { await typing.poll(contactId: thread.contactId) }
    }

    // BOREAL_DIALER_v803_UI - "+1 (403) 555-0142" under the name in the header.
    private var headerSubtitle: String {
        let formatted = PhoneFormat.display(thread.phone)
        if formatted.hasPrefix("(") { return "+1 " + formatted }
        return formatted
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
                    SendSMSPayload(to: to, body: text, contactId: thread.contactId, media: media)
                )
                draft = ""
                media = nil
                photoItem = nil
                await loadMessages()
                onChange()
            } catch {
                self.error = "Couldn't send that message. Please try again."
            }
            sending = false
        }
    }
}

// BOREAL_DIALER_BLOCK_v501_SMS_PARITY - photo and PDF loading, 5 MB MMS limit.
extension SMSThreadView {
    static let maxMediaBytes = 5 * 1024 * 1024

    @MainActor func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            error = "Couldn't read that photo."
            return
        }
        var jpeg = image.jpegData(compressionQuality: 0.7)
        if let current = jpeg, current.count > Self.maxMediaBytes {
            let scale = 2048.0 / max(image.size.width, image.size.height)
            if scale < 1 {
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                jpeg = resized.jpegData(compressionQuality: 0.6)
            }
        }
        guard let final = jpeg, final.count <= Self.maxMediaBytes else {
            error = "That photo is too large to text (5 MB limit)."
            return
        }
        error = nil
        media = SMSMediaPayload(name: "photo.jpg", contentType: "image/jpeg", dataUrl: "data:image/jpeg;base64," + final.base64EncodedString())
    }

    @MainActor func loadPdf(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            error = "Couldn't read that PDF."
            return
        }
        guard data.count <= Self.maxMediaBytes else {
            error = "Files sent by text must be 5 MB or smaller."
            return
        }
        error = nil
        media = SMSMediaPayload(name: url.lastPathComponent, contentType: "application/pdf", dataUrl: "data:application/pdf;base64," + data.base64EncodedString())
    }
}

private struct SMSBubble: View {
    let message: SMSMessage

    var body: some View {
        HStack {
            if message.isOutbound { Spacer(minLength: 40) }

            VStack(alignment: message.isOutbound ? .trailing : .leading, spacing: 4) {
                if message.hasMedia, let url = mediaURL {
                    // BOREAL_DIALER_URL_TICKET_v790 - loaded with the Authorization header, not a token in the URL.
                    AuthorizedMediaImage(url: url)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // BOREAL_DIALER_THREAD_STYLE_v32
                if let body = message.body, !body.isEmpty {
                    ChatBubble(outbound: message.isOutbound) { Text(body) }
                }

                Text(message.timeLabel)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.faint)

                // BOREAL_DIALER_BLOCK_v501_SMS_PARITY - delivery result (portal v500)
                if message.isOutbound, let tag = SmsDelivery.tag(status: message.deliveryStatus, errorCode: message.deliveryError) {
                    Text(tag.text)
                        .font(.system(size: 12, weight: tag.tone == .error ? .semibold : .regular))
                        .foregroundColor(tag.tone == .error ? Theme.red : (tag.tone == .success ? Theme.green : Theme.faint))
                        .multilineTextAlignment(.trailing)
                }
            }

            if !message.isOutbound { Spacer(minLength: 40) }
        }
    }
}

private extension SMSBubble {
    // Twilio media needs Basic auth, so it is proxied by the server.
    // BOREAL_DIALER_URL_TICKET_v790 - no token in the URL; AuthorizedMediaImage
    // sends the Authorization header (BF-Server v789 refuses ?token= sign-in tokens).
    var mediaURL: URL? {
        guard message.hasMedia else { return nil }
        return URL(string: "\(APIConfig.baseURL)/communications/messages/\(message.id)/media")
    }
}
