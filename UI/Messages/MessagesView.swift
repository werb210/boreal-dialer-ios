// BOREAL_DIALER_SERVER_THREADS_v3
// The Messages tab is the unified inbox across SMS, chat and email. It reads
// GET /api/communications/threads on BF-Server, which resolves the silo from
// the X-Silo header and returns one row per conversation. Going through the
// server is what puts staff activity on the contact timeline; the previous
// Twilio Conversations client talked to Twilio directly and logged nothing.
import SwiftUI

struct CommunicationThread: Identifiable, Decodable {
    let id: String
    let type: String?
    let silo: String?
    let contactName: String?
    let contactPhone: String?
    let contactEmail: String?
    let unread: Int?
    let message: String?
    let updatedAt: String?

    var channelLabel: String {
        switch (type ?? "").lowercased() {
        case "sms": return "SMS"
        case "human", "chat": return "Chat"
        default: return "Message"
        }
    }

    var title: String {
        contactName ?? contactPhone ?? contactEmail ?? "Unknown contact"
    }
}

@MainActor
final class MessagesViewModel: ObservableObject {
    @Published var threads: [CommunicationThread] = []
    @Published var loading = false
    @Published var error: String?
    @Published var channelFilter: String = "All"

    let filters = ["All", "SMS", "Chat"]

    var visibleThreads: [CommunicationThread] {
        guard channelFilter != "All" else { return threads }
        return threads.filter { $0.channelLabel == channelFilter }
    }

    func load() async {
        loading = true
        error = nil
        do {
            let request = try APIClient.shared.makeRequest(path: "/communications/threads")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            threads = try JSONDecoder().decode([CommunicationThread].self, from: data)
        } catch {
            self.error = "Could not load messages."
        }
        loading = false
    }
}

struct MessagesView: View {
    @StateObject private var viewModel = MessagesViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Messages").font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Picker("Channel", selection: $viewModel.channelFilter) {
                ForEach(viewModel.filters, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            if viewModel.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.visibleThreads.isEmpty {
                Text(viewModel.error ?? "No conversations")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.visibleThreads) { thread in
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
                                Text(preview).font(.subheadline)
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
                .listStyle(.plain)
                .refreshable { await viewModel.load() }
            }
        }
        .task { await viewModel.load() }
    }
}
