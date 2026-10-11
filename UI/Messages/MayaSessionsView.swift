// BOREAL_DIALER_MAYA_SESSIONS_v789 - Maya's live website chats, read-only, in the
// Messages area (portal parity). BF-Server:
//   GET /api/communications/maya-sessions
//   GET /api/communications/maya-sessions/:id/messages
// Decoding is tolerant: snake_case or camelCase, missing fields, and either a
// bare array or one wrapped in {sessions|messages|items|data}.
import Foundation
import SwiftUI
import UIKit

struct MayaSession: Identifiable, Decodable, Equatable {
    let id: String
    let contactName: String?
    let contactId: String?
    let status: String?
    let lastMessage: String?
    let updatedAt: String?

    var title: String {
        if let name = contactName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        return "Website visitor"
    }

    init(id: String, contactName: String?, contactId: String?, status: String?, lastMessage: String?, updatedAt: String?) {
        self.id = id
        self.contactName = contactName
        self.contactId = contactId
        self.status = status
        self.lastMessage = lastMessage
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, sessionId, session_id
        case contactName, contact_name, visitorName, visitor_name, name
        case contactId, contact_id
        case status
        case lastMessage, last_message, preview
        case updatedAt, updated_at, lastMessageAt, last_message_at, createdAt, created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = TeamLossy.string(c, .id) ?? TeamLossy.string(c, .sessionId) ?? TeamLossy.string(c, .session_id) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "session id"))
        }
        self.id = id
        contactName = TeamLossy.string(c, .contactName) ?? TeamLossy.string(c, .contact_name)
            ?? TeamLossy.string(c, .visitorName) ?? TeamLossy.string(c, .visitor_name) ?? TeamLossy.string(c, .name)
        contactId = TeamLossy.string(c, .contactId) ?? TeamLossy.string(c, .contact_id)
        status = TeamLossy.string(c, .status)
        lastMessage = TeamLossy.string(c, .lastMessage) ?? TeamLossy.string(c, .last_message) ?? TeamLossy.string(c, .preview)
        updatedAt = TeamLossy.string(c, .updatedAt) ?? TeamLossy.string(c, .updated_at)
            ?? TeamLossy.string(c, .lastMessageAt) ?? TeamLossy.string(c, .last_message_at)
            ?? TeamLossy.string(c, .createdAt) ?? TeamLossy.string(c, .created_at)
    }
}

struct MayaMessage: Identifiable, Decodable, Equatable {
    let id: String
    let role: String
    let body: String
    let createdAt: String?

    /// Maya / the assistant on one side, the visitor on the other.
    var fromMaya: Bool {
        ["assistant", "maya", "bot", "ai", "system"].contains(role.lowercased())
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, sender, author, from
        case body, content, text, message
        case createdAt, created_at, timestamp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        body = TeamLossy.string(c, .body) ?? TeamLossy.string(c, .content)
            ?? TeamLossy.string(c, .text) ?? TeamLossy.string(c, .message) ?? ""
        role = TeamLossy.string(c, .role) ?? TeamLossy.string(c, .sender)
            ?? TeamLossy.string(c, .author) ?? TeamLossy.string(c, .from) ?? "user"
        createdAt = TeamLossy.string(c, .createdAt) ?? TeamLossy.string(c, .created_at) ?? TeamLossy.string(c, .timestamp)
        id = TeamLossy.string(c, .id) ?? "\(role)|\(createdAt ?? "")|\(body.hashValue)"
    }
}

@MainActor
final class MayaSessionsViewModel: ObservableObject {
    @Published private(set) var sessions: [MayaSession] = []
    @Published private(set) var messages: [MayaMessage] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    nonisolated static func messagesPath(sessionId: String) -> String {
        "/communications/maya-sessions/\(TeamParityStore.pathSegment(sessionId))/messages"
    }

    func loadSessions() async {
        loading = true
        error = nil
        do {
            let request = try APIClient.shared.makeRequest(path: "/communications/maya-sessions")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            sessions = TeamLossy.list(MayaSession.self, from: data, keys: ["sessions", "items", "data"])
        } catch {
            self.error = "Could not load Maya chats."
        }
        loading = false
    }

    func loadMessages(sessionId: String) async {
        loading = true
        error = nil
        do {
            let request = try APIClient.shared.makeRequest(path: Self.messagesPath(sessionId: sessionId))
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            messages = TeamLossy.list(MayaMessage.self, from: data, keys: ["messages", "items", "data"])
        } catch {
            self.error = "Could not load this chat."
        }
        loading = false
    }
}

struct MayaSessionsView: View {
    @StateObject private var viewModel = MayaSessionsViewModel()

    var body: some View {
        Group {
            if viewModel.loading && viewModel.sessions.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.sessions.isEmpty {
                Text(viewModel.error ?? "No Maya chats")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.sessions) { session in
                    NavigationLink {
                        MayaSessionDetailView(session: session)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(session.title).font(.system(size: 15.5, weight: .semibold))
                                Spacer()
                                if let status = session.status, !status.isEmpty {
                                    Text(status.capitalized).font(.caption).foregroundColor(Theme.muted)
                                }
                            }
                            if let last = session.lastMessage, !last.isEmpty {
                                Text(last).font(.system(size: 13)).foregroundColor(Theme.muted).lineLimit(2)
                            }
                            if let at = session.updatedAt {
                                Text(DialerDashboardStore.time(TeamLossy.date(at))).font(.caption2).foregroundColor(Theme.faint)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
                .refreshable { await viewModel.loadSessions() }
            }
        }
        .navigationTitle("Maya chats")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadSessions() }
    }
}

/// Read-only: staff watch the conversation here; replying stays in the portal.
struct MayaSessionDetailView: View {
    let session: MayaSession
    @StateObject private var viewModel = MayaSessionsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if viewModel.messages.isEmpty {
                    Text(viewModel.loading ? "Loading..." : (viewModel.error ?? "No messages yet"))
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                }
                ForEach(viewModel.messages) { message in
                    HStack {
                        if !message.fromMaya { Spacer(minLength: 40) }
                        VStack(alignment: message.fromMaya ? .leading : .trailing, spacing: 2) {
                            Text(message.fromMaya ? "Maya" : session.title)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(message.body)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(message.fromMaya ? Color(.systemGray5) : Theme.green.opacity(0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        if message.fromMaya { Spacer(minLength: 40) }
                    }
                }
            }
            .padding()
        }
        .background(Theme.bg)
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.loadMessages(sessionId: session.id) }
        .task { await viewModel.loadMessages(sessionId: session.id) }
    }
}
