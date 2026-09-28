import Foundation
import SwiftUI
import UIKit // BOREAL_DIALER_TEAM_PHASE_B_v667 - UIPasteboard for Copy

struct TeamMessage: Identifiable, Decodable, Equatable {
    let id: String
    let channel_id: String
    let sender_id: String?
    let body: String
    let created_at: String?
    // BOREAL_DIALER_TEAM_PHASE_B_v667 - replies are grouped under a root message.
    let thread: TeamThreadSummary?
    let thread_root_id: String?
}

struct TeamChannel: Identifiable, Decodable {
    let id: String
    let kind: String
    let name: String?
    let member_ids: [String]
    let last_message: TeamMessage?
    let unread_count: Int
    // BOREAL_DIALER_TEAM_PHASE_B_v667
    let topic: String?
    let is_private: Bool?
    let archived_at: String?
    let muted: Bool?
    let has_mention: Bool?
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
            return channel.kind == "channel" ? ((channel.is_private ?? false) ? "\u{1F512} " : "# ") + name : name
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

    func createChannel(kind: String, name: String, memberIds: [String], topic: String = "", isPrivate: Bool = false) async -> String? {
        do {
            var obj: [String: Any] = ["kind": kind, "member_ids": memberIds]
            if kind != "dm" { obj["name"] = name }
            if kind == "channel" { obj["topic"] = topic; obj["is_private"] = isPrivate } // BOREAL_DIALER_TEAM_PHASE_B_v667
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
            } else if type == "thread_message" || type == "status" {
                TeamPhaseBStore.shared.handleSocket(obj)
                if type == "thread_message", let channelId = obj["channel_id"] as? String, channelId == activeId { await open(channelId) }
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
    // BOREAL_DIALER_TEAM_PHASE_B_v667
    @ObservedObject private var extras = TeamPhaseBStore.shared
    @State private var showBrowse = false
    @State private var showSearch = false
    @State private var showStatus = false
    @State private var openTarget: TeamOpenTarget?

    private var myStatusLabel: String {
        guard let me = store.myId, let line = extras.statusLine(for: me) else { return "Set status" }
        return line
    }

    private func openLater(_ target: TeamOpenTarget) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { openTarget = target }
    }

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
                                    if let line = extras.statusLine(for: user.id) {
                                        Text(line).font(.system(size: 12)).foregroundColor(Theme.muted).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Text(extras.isAway(user.id) && store.status(for: user.id) != "offline" ? "Away" : store.status(for: user.id).capitalized)
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
                                        Text(store.label(channel) + (channel.archived_at == nil ? "" : " (archived)"))
                                            .font(.system(size: 15.5, weight: .semibold))
                                            .opacity(channel.archived_at == nil ? 1 : 0.55)
                                        if let lastMessage = channel.last_message {
                                            Text(lastMessage.body)
                                                .font(.system(size: 13))
                                                .foregroundColor(Theme.muted)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if channel.has_mention ?? false {
                                        Text("@").font(.caption.bold()).foregroundColor(.white).padding(.horizontal, 5).background(Theme.green).clipShape(Capsule())
                                    }
                                    if channel.muted ?? false { Image(systemName: "bell.slash").foregroundColor(Theme.muted) }
                                    if channel.unread_count > 0 {
                                        CountBadge(count: channel.unread_count)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button((channel.muted ?? false) ? "Unmute" : "Mute") { Task { await extras.setMuted(channel.id, muted: !(channel.muted ?? false)) } }
                                    .tint(Theme.muted)
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
            .background(
                NavigationLink(isActive: Binding(get: { openTarget != nil }, set: { if !$0 { openTarget = nil } })) {
                    if let target = openTarget { TeamChannelView(channelId: target.channelId, title: target.title, openThreadId: target.threadRootId) }
                } label: { EmptyView() }
            )
            .navigationTitle("Team")
            .navigationBarItems(
                leading: Button { showStatus = true } label: { Text(myStatusLabel).font(.footnote).lineLimit(1) },
                trailing: HStack(spacing: 16) {
                    Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                    Button { showBrowse = true } label: { Image(systemName: "number") }
                    Button { showNew = true } label: { Image(systemName: "square.and.pencil") }
                }
            )
            .sheet(isPresented: $showBrowse) { TeamBrowseView { id, title in openLater(TeamOpenTarget(channelId: id, title: title, threadRootId: nil)) } }
            .sheet(isPresented: $showSearch) { TeamSearchView { id, title, root in openLater(TeamOpenTarget(channelId: id, title: title, threadRootId: root)) } }
            .sheet(isPresented: $showStatus) { TeamStatusView() }
            .sheet(isPresented: $showNew) {
                NewTeamChatView { kind, name, ids, topic, isPrivate in
                    Task {
                        if let id = await store.createChannel(kind: kind, name: name, memberIds: ids, topic: topic, isPrivate: isPrivate) {
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
            await TeamPhaseBStore.shared.loadStatuses() // BOREAL_DIALER_TEAM_PHASE_B_v667
            TeamPhaseBStore.shared.startIdleAway()
            // BOREAL_DIALER_TEAM_ROSTER_v28 - the server marks a staff member
            // offline five minutes after their last heartbeat, so a roster
            // fetched once at launch goes wrong quickly.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                await store.loadPresence()
                await TeamPhaseBStore.shared.loadStatuses()
            }
        }
        .onDisappear { store.disconnect() }
    }
}

struct TeamChannelView: View {
    // BOREAL_DIALER_THREAD_SCROLL_v166
    // BOREAL_DIALER_SCROLL_BOTTOM_v649 - jump to a fixed marker after the last message, and try
    // again as rows and pictures finish laying out (one early jump often stopped part-way).
    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !store.messages.isEmpty else { return }
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

    let channelId: String
    let title: String
    var openThreadId: String? = nil
    @ObservedObject private var extras = TeamPhaseBStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var threadTarget: String?
    @State private var showDetails = false
    @ObservedObject private var store = TeamStore.shared
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            if let topic = channel?.topic, !topic.isEmpty {
                Text(topic).font(.footnote).foregroundColor(.secondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.vertical, 6)
            }
            // BOREAL_DIALER_THREAD_SCROLL_v166
            // This channel view had no ScrollViewReader at all, so it never
            // scrolled to the newest message under any circumstance - not on
            // open, not when a message arrived.
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) { // BOREAL_DIALER_SCROLL_BOTTOM_v649
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
                                TeamFormattedText(text: message.body)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(mine ? Color.accentColor : Color(.systemGray5))
                                    .foregroundColor(mine ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .contextMenu {
                                        Button { threadTarget = message.id } label: { Label("Reply in thread", systemImage: "bubble.left.and.bubble.right") }
                                        Button { Task { await extras.markUnread(channelId, messageId: message.id) } } label: { Label("Mark unread from here", systemImage: "circle.fill") }
                                        Button { UIPasteboard.general.string = message.body } label: { Label("Copy", systemImage: "doc.on.doc") }
                                    }
                                // BOREAL_DIALER_BLOCK_v506_TEAM_LINK_PREVIEWS
                                TeamLinkPreviewCard(text: message.body)
                                if let thread = message.thread, thread.reply_count > 0 {
                                    Button { threadTarget = message.id } label: { Text("\u{1F4AC} \(thread.reply_count) \(thread.reply_count == 1 ? "reply" : "replies")").font(.caption.weight(.semibold)) }.buttonStyle(.borderless)
                                }
                            }
                            if !mine { Spacer() }
                        }
                        // BOREAL_DIALER_THREAD_SCROLL_v166 - explicit id so
                        // proxy.scrollTo has a row to target.
                        .id(message.id)
                    }
                    ThreadBottom()
                }
                .padding()
            }
            .onAppear { scrollToLatest(proxy, animated: false) }
            .onChange(of: store.messages.count) { _ in
                scrollToLatest(proxy, animated: true)
            }
            .onChange(of: store.messages.last?.id) { _ in scrollToLatest(proxy, animated: true) }
            }
            Divider()
            HStack {
                TextField(channel?.archived_at != nil ? "This channel is archived" : "Message", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.roundedBorder)
                    .disabled(channel?.archived_at != nil)
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
        .navigationBarItems(trailing: Group {
            if let channel, channel.kind != "dm" { Button { showDetails = true } label: { Image(systemName: "info.circle") } }
        })
        .sheet(isPresented: $showDetails) { if let channel { TeamChannelDetailsView(channel: channel, onLeft: { dismiss() }) } }
        .background(
            NavigationLink(isActive: Binding(get: { threadTarget != nil }, set: { if !$0 { threadTarget = nil } })) {
                if let root = threadTarget { TeamThreadView(channelId: channelId, rootId: root, archived: channel?.archived_at != nil) }
            } label: { EmptyView() }
        )
        .task { await store.open(channelId); if let openThreadId { threadTarget = openThreadId } }
    }

    private var channel: TeamChannel? { store.channels.first { $0.id == channelId } }
}

struct NewTeamChatView: View {
    let onCreate: (_ kind: String, _ name: String, _ memberIds: [String], _ topic: String, _ isPrivate: Bool) -> Void
    @ObservedObject private var store = TeamStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "dm"
    @State private var name = ""
    @State private var topic = ""
    @State private var isPrivate = false
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
                if mode == "channel" {
                    TextField("Topic (optional)", text: $topic)
                    Toggle("Private (only people you add)", isOn: $isPrivate)
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
                trailing: Button("Create") { onCreate(mode, name, Array(picked), topic, isPrivate) }.disabled(!canCreate)
            )
        }
        .navigationViewStyle(.stack)
    }
}
