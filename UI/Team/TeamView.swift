import Foundation
import SwiftUI

struct TeamMessage: Identifiable, Decodable, Equatable {
    let id: String
    let channel_id: String
    let sender_id: String?
    let body: String
    let created_at: String?
}

struct TeamChannel: Identifiable, Decodable {
    let id: String
    let kind: String
    let name: String?
    let member_ids: [String]
    let last_message: TeamMessage?
    let unread_count: Int
}

struct TeamUser: Identifiable, Decodable {
    let id: String
    let name: String
    let email: String?
}

@MainActor
final class TeamStore: ObservableObject {
    static let shared = TeamStore()

    @Published var channels: [TeamChannel] = []
    @Published var users: [TeamUser] = []
    // BOREAL_DIALER_TABS_PRESENTATION_v26
    @Published var presence: [String: String] = [:]
    @Published var messages: [TeamMessage] = []
    @Published var activeId: String?

    private var ws: URLSessionWebSocketTask?

    var myId: String? {
        guard let token = TokenStorage.shared.getToken() else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (obj["sub"] as? String) ?? (obj["id"] as? String)
    }

    // BOREAL_DIALER_TABS_PRESENTATION_v26
    func loadPresence() async {
        struct Row: Decodable { let user_id: String; let status: String }
        struct Resp: Decodable { let presence: [Row] }
        do {
            let req = try APIClient.shared.makeRequest(path: "/team/presence")
            let data = try await APIClient.shared.makeAuthorizedRequest(req)
            let rows = try JSONDecoder().decode(Resp.self, from: data).presence
            presence = Dictionary(rows.map { ($0.user_id, $0.status) }, uniquingKeysWith: { _, b in b })
        } catch {
            // Presence is decoration; the roster still lists everyone.
            presence = [:]
        }
    }

    // Staff with no presence row have never connected, which reads as offline.
    func status(for userId: String) -> String {
        (presence[userId] ?? "offline").lowercased()
    }

    // BOREAL_DIALER_TEAM_ROSTER_SELF_v50
    // The roster listed EVERY user, including the signed-in staff member and
    // the client-submission@system.local placeholder that owns client-submitted
    // applications. myId was already computed but only used to hide the call
    // button, so you appeared in your own team list with no way to call
    // yourself - and, being the only person usually marked available, you made
    // the header read "Available · 1" about yourself.
    //
    // Pure and static so the filtering is exercised by the test target rather
    // than only by looking at it. The system account is identified by its
    // @system.local address; there is no flag on /team/users to key off, and
    // adding one server-side would change the staff portal's roster too.
    // BOREAL_DIALER_ROSTER_NONISOLATED_v53 - TeamStore is @MainActor, so this
    // static method inherited main-actor isolation and every call from the
    // nonisolated XCTestCase methods was an error under Xcode 26:
    // "call to main actor-isolated static method in a synchronous nonisolated
    // context". It reads only its arguments and touches no actor state, so it
    // has no business being isolated. rosterSections still calls it from the
    // main actor, which nonisolated permits.
    nonisolated static func rosterMembers(users: [TeamUser], excluding myId: String?) -> [TeamUser] {
        users.filter { user in
            if let myId, user.id == myId { return false }
            if let email = user.email?.lowercased(), email.hasSuffix("@system.local") { return false }
            return true
        }
    }

    var rosterSections: [(String, [TeamUser])] {
        let order = ["available", "away", "offline"]
        let titles = ["available": "Available", "away": "Away", "offline": "Offline"]
        var buckets: [String: [TeamUser]] = [:]
        for user in Self.rosterMembers(users: users, excluding: myId) {
            let key = order.contains(status(for: user.id)) ? status(for: user.id) : "offline"
            buckets[key, default: []].append(user)
        }
        return order.compactMap { key in
            guard let group = buckets[key], !group.isEmpty else { return nil }
            return ("\(titles[key] ?? key) · \(group.count)", group)
        }
    }

    func name(for id: String?) -> String {
        guard let id else { return "Staff" }
        return users.first(where: { $0.id == id })?.name ?? "Staff"
    }

    func label(_ channel: TeamChannel) -> String {
        if let name = channel.name, !name.isEmpty {
            return channel.kind == "channel" ? "# \(name)" : name
        }

        let others = channel.member_ids.filter { $0 != myId }.map { name(for: $0) }
        return others.isEmpty ? "Direct message" : others.joined(separator: ", ")
    }

    func loadChannels() async {
        do {
            let req = try APIClient.shared.makeRequest(path: "/team/channels")
            let data = try await APIClient.shared.makeAuthorizedRequest(req)
            struct Resp: Decodable { let channels: [TeamChannel] }
            channels = try JSONDecoder().decode(Resp.self, from: data).channels
        } catch { /* ignore */ }
    }

    func loadUsers() async {
        do {
            let req = try APIClient.shared.makeRequest(path: "/team/users")
            let data = try await APIClient.shared.makeAuthorizedRequest(req)
            struct Resp: Decodable { let users: [TeamUser] }
            users = try JSONDecoder().decode(Resp.self, from: data).users
            await loadPresence()
        } catch { /* ignore */ }
    }

    func open(_ id: String) async {
        activeId = id
        do {
            let req = try APIClient.shared.makeRequest(path: "/team/channels/\(id)/messages")
            let data = try await APIClient.shared.makeAuthorizedRequest(req)
            struct Resp: Decodable { let messages: [TeamMessage] }
            messages = try JSONDecoder().decode(Resp.self, from: data).messages
        } catch {
            messages = []
        }
        await markRead(id)
        await loadChannels()
    }

    func markRead(_ id: String) async {
        if let req = try? APIClient.shared.makeRequest(path: "/team/channels/\(id)/read", method: "POST") {
            _ = try? await APIClient.shared.makeAuthorizedRequest(req)
        }
    }

    func send(_ body: String) async {
        guard let id = activeId else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let payload = try JSONSerialization.data(withJSONObject: ["body": trimmed])
            let req = try APIClient.shared.makeRequest(path: "/team/channels/\(id)/messages", method: "POST", body: payload)
            let data = try await APIClient.shared.makeAuthorizedRequest(req)
            struct Resp: Decodable { let message: TeamMessage }
            let message = try JSONDecoder().decode(Resp.self, from: data).message
            if !messages.contains(where: { $0.id == message.id }) {
                messages.append(message)
            }
            await loadChannels()
        } catch { /* ignore */ }
    }

    func createChannel(kind: String, name: String, memberIds: [String]) async -> String? {
        do {
            var obj: [String: Any] = ["kind": kind, "member_ids": memberIds]
            if kind != "dm" { obj["name"] = name }
            let payload = try JSONSerialization.data(withJSONObject: obj)
            let req = try APIClient.shared.makeRequest(path: "/team/channels", method: "POST", body: payload)
            let data = try await APIClient.shared.makeAuthorizedRequest(req)
            struct Resp: Decodable { let channel_id: String }
            return try JSONDecoder().decode(Resp.self, from: data).channel_id
        } catch {
            return nil
        }
    }

    func connect() {
        guard ws == nil,
              let token = TokenStorage.shared.getToken(),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "wss://server.boreal.financial/api/team/ws?token=\(encodedToken)") else { return }
        let task = URLSession.shared.webSocketTask(with: url)
        ws = task
        task.resume()
        receive(on: task)
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            guard let self, let task else { return }
            Task { @MainActor in
                guard self.ws === task else { return }
                if case .success(let message) = result {
                    await self.handle(message)
                    self.receive(on: task)
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) async {
        if case .string(let text) = message,
           let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let type = obj["type"] as? String
            if type == "message" {
                await loadChannels()
                if let channelId = obj["channel_id"] as? String, channelId == activeId {
                    await open(channelId)
                }
            } else if type == "channel" {
                await loadChannels()
            }
        }
    }

    func disconnect() {
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
    }
}

struct TeamView: View {
    @StateObject private var store = TeamStore.shared
    @State private var showNew = false
    // BOREAL_DIALER_TEAM_ROSTER_v28
    @State private var search = ""

    private var roster: [(String, [TeamUser])] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return store.rosterSections }
        return store.rosterSections.compactMap { title, members in
            let filtered = members.filter { $0.name.lowercased().contains(query) }
            return filtered.isEmpty ? nil : (title, filtered)
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(Theme.muted)
                        TextField("Search staff", text: $search)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                    }
                    .padding(9)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                // Presence roster. Tapping a teammate places an internal VOIP
                // call through the same conference endpoint as a PSTN call, so
                // the mid-call controls work on it.
                ForEach(roster, id: \.0) { title, members in
                    Section {
                        ForEach(members) { user in
                            HStack(spacing: 13) {
                                AvatarCircle(
                                    name: user.name,
                                    size: 40,
                                    presence: store.status(for: user.id)
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.name)
                                        .font(.system(size: 15.5, weight: .semibold))
                                    if let email = user.email, !email.isEmpty {
                                        Text(email)
                                            .font(.system(size: 13))
                                            .foregroundColor(Theme.muted)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Text(store.status(for: user.id).capitalized)
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.faint)
                                if user.id != store.myId {
                                    Button {
                                        // BOREAL_DIALER_JOIN_CONFERENCE_v46
                                        VoiceEngine.shared.startInternalCall(
                                            staffIdentity: user.id,
                                            displayName: user.name
                                        )
                                    } label: {
                                        Image(systemName: "phone.fill")
                                            .foregroundColor(Theme.green)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        SectionLabel(text: title)
                    }
                }

                if !store.channels.isEmpty {
                    Section {
                        ForEach(store.channels) { channel in
                            NavigationLink {
                                TeamChannelView(channelId: channel.id, title: store.label(channel))
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(store.label(channel))
                                            .font(.system(size: 15.5, weight: .semibold))
                                        if let lastMessage = channel.last_message {
                                            Text(lastMessage.body)
                                                .font(.system(size: 13))
                                                .foregroundColor(Theme.muted)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if channel.unread_count > 0 {
                                        CountBadge(count: channel.unread_count)
                                    }
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        SectionLabel(text: "Channels")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Team")
            .navigationBarItems(trailing: Button { showNew = true } label: { Image(systemName: "square.and.pencil") })
            .sheet(isPresented: $showNew) {
                NewTeamChatView { kind, name, ids in
                    Task {
                        if let id = await store.createChannel(kind: kind, name: name, memberIds: ids) {
                            await store.loadChannels()
                            await store.open(id)
                        }
                        showNew = false
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task {
            await store.loadUsers()
            await store.loadChannels()
            store.connect()
            // BOREAL_DIALER_TEAM_ROSTER_v28 - the server marks a staff member
            // offline five minutes after their last heartbeat, so a roster
            // fetched once at launch goes wrong quickly.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                await store.loadPresence()
            }
        }
        .onDisappear { store.disconnect() }
    }
}

struct TeamChannelView: View {
    let channelId: String
    let title: String
    @ObservedObject private var store = TeamStore.shared
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(store.messages) { message in
                        let mine = message.sender_id == store.myId
                        HStack {
                            if mine { Spacer() }
                            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                                if !mine {
                                    Text(store.name(for: message.sender_id))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text(message.body)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(mine ? Color.accentColor : Color(.systemGray5))
                                    .foregroundColor(mine ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            if !mine { Spacer() }
                        }
                    }
                }
                .padding()
            }
            Divider()
            HStack {
                TextField("Message…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let body = draft
                    draft = ""
                    Task { await store.send(body) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.open(channelId) }
    }
}

struct NewTeamChatView: View {
    let onCreate: (_ kind: String, _ name: String, _ memberIds: [String]) -> Void
    @ObservedObject private var store = TeamStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "dm"
    @State private var name = ""
    @State private var picked: Set<String> = []

    private var canCreate: Bool {
        if mode == "dm" { return picked.count == 1 }
        if mode == "group" { return !picked.isEmpty }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Picker("Type", selection: $mode) {
                    Text("Direct").tag("dm")
                    Text("Group").tag("group")
                    Text("Channel").tag("channel")
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _ in picked.removeAll() }

                if mode != "dm" {
                    TextField(mode == "channel" ? "Channel name" : "Group name (optional)", text: $name)
                }

                Section(mode == "dm" ? "Pick one person" : "Pick people") {
                    ForEach(store.users.filter { $0.id != store.myId }) { user in
                        Button {
                            if picked.contains(user.id) {
                                picked.remove(user.id)
                            } else {
                                if mode == "dm" { picked.removeAll() }
                                picked.insert(user.id)
                            }
                        } label: {
                            HStack {
                                Text(user.name).foregroundColor(.primary)
                                Spacer()
                                if picked.contains(user.id) {
                                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New conversation")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button("Create") { onCreate(mode, name, Array(picked)) }.disabled(!canCreate)
            )
        }
        .navigationViewStyle(.stack)
    }
}
