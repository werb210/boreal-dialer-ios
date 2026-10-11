// BOREAL_DIALER_TEAM_PARITY_v789 - Team chat catches up with the portal: edit and
// delete your own messages, reactions, pins and the pinned list, typing
// indicators, search inside one conversation and who has seen it. BF-Server
// endpoints (staff auth, X-Silo from APIClient.makeRequest):
//   PATCH  /api/team/channels/:id/messages/:mid             {body}
//   DELETE /api/team/channels/:id/messages/:mid
//   POST   /api/team/channels/:id/messages/:mid/reactions   {emoji}
//   DELETE /api/team/channels/:id/messages/:mid/reactions?emoji=<emoji>
//   POST   /api/team/channels/:id/messages/:mid/pin         (toggle)
//   GET    /api/team/channels/:id/pins
//   POST   /api/team/channels/:id/typing                    (at most every 3 s)
//   GET    /api/team/channels/:id/search?q=
//   GET    /api/team/channels/:id/reads
// Others' typing arrives on the team websocket as {type: "typing"}.
import Foundation
import SwiftUI

// MARK: - Tolerant decoding

enum TeamLossy {
    /// A string field that may arrive as a string or a number, or be absent/null.
    static func string<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> String? {
        if let value = try? c.decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? c.decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return nil
    }

    /// Server timestamps come with or without fractional seconds.
    static func date(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    /// Decodes the first of `keys` that holds an array of T, or a bare array.
    static func list<T: Decodable>(_ type: T.Type, from data: Data, keys: [String]) -> [T] {
        if let items = try? JSONDecoder().decode(TeamLossyArray<T>.self, from: data) { return items.items }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        for key in keys {
            guard let raw = object[key], JSONSerialization.isValidJSONObject(raw),
                  let nested = try? JSONSerialization.data(withJSONObject: raw),
                  let items = try? JSONDecoder().decode(TeamLossyArray<T>.self, from: nested) else { continue }
            return items.items
        }
        return []
    }
}

/// An array that skips elements that fail to decode instead of failing whole.
struct TeamLossyArray<T: Decodable>: Decodable {
    let items: [T]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var out: [T] = []
        while !container.isAtEnd {
            if let item = try? container.decode(T.self) {
                out.append(item)
            } else if (try? container.decode(TeamSkip.self)) == nil {
                break // cannot step past it; keep what decoded so far
            }
        }
        items = out
    }
}

/// Consumes one element of any shape without reading it.
private struct TeamSkip: Decodable {
    init(from decoder: Decoder) throws {}
}

struct TeamReaction: Decodable, Equatable, Hashable {
    let emoji: String
    let count: Int
    let user_ids: [String]

    init(emoji: String, count: Int, user_ids: [String]) {
        self.emoji = emoji
        self.count = count
        self.user_ids = user_ids
    }

    private enum CodingKeys: String, CodingKey { case emoji, count, user_ids, users, userIds, user_id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let emoji = TeamLossy.string(c, .emoji), !emoji.isEmpty else {
            throw DecodingError.keyNotFound(CodingKeys.emoji, .init(codingPath: c.codingPath, debugDescription: "emoji"))
        }
        self.emoji = emoji
        var ids = (try? c.decodeIfPresent([String].self, forKey: .user_ids))
            ?? (try? c.decodeIfPresent([String].self, forKey: .userIds))
            ?? (try? c.decodeIfPresent([String].self, forKey: .users))
            ?? []
        if ids.isEmpty, let single = TeamLossy.string(c, .user_id) { ids = [single] }
        user_ids = ids
        count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? max(ids.count, 1)
    }
}

/// Reactions arrive as [{emoji, count, user_ids}] or as {emoji: [user ids]} /
/// {emoji: count}. Either way the result is one row per emoji.
struct TeamReactionList: Decodable {
    let items: [TeamReaction]

    init(from decoder: Decoder) throws {
        if let array = try? TeamLossyArray<TeamReaction>(from: decoder) {
            items = TeamParityStore.merged(array.items)
            return
        }
        let container = try decoder.singleValueContainer()
        if let byUsers = try? container.decode([String: [String]].self) {
            items = byUsers.keys.sorted().compactMap { emoji in
                guard let ids = byUsers[emoji], !ids.isEmpty else { return nil }
                return TeamReaction(emoji: emoji, count: ids.count, user_ids: ids)
            }
        } else if let byCount = try? container.decode([String: Int].self) {
            items = byCount.keys.sorted().compactMap { emoji in
                guard let count = byCount[emoji], count > 0 else { return nil }
                return TeamReaction(emoji: emoji, count: count, user_ids: [])
            }
        } else {
            items = []
        }
    }
}

struct TeamChannelRead: Decodable, Equatable, Identifiable {
    let user_id: String
    let read_at: String?
    let message_id: String?

    var id: String { user_id }

    init(user_id: String, read_at: String?, message_id: String?) {
        self.user_id = user_id
        self.read_at = read_at
        self.message_id = message_id
    }

    private enum CodingKeys: String, CodingKey {
        case user_id, userId, read_at, last_read_at, readAt, message_id, last_read_message_id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let user = TeamLossy.string(c, .user_id) ?? TeamLossy.string(c, .userId) else {
            throw DecodingError.keyNotFound(CodingKeys.user_id, .init(codingPath: c.codingPath, debugDescription: "user_id"))
        }
        user_id = user
        read_at = TeamLossy.string(c, .last_read_at) ?? TeamLossy.string(c, .read_at) ?? TeamLossy.string(c, .readAt)
        message_id = TeamLossy.string(c, .last_read_message_id) ?? TeamLossy.string(c, .message_id)
    }
}

/// A pinned entry is either the message itself or {message: {...}}.
private struct TeamPinEntry: Decodable {
    let message: TeamMessage

    private enum CodingKeys: String, CodingKey { case message }

    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let nested = try? c.decode(TeamMessage.self, forKey: .message) {
            message = nested
        } else {
            message = try TeamMessage(from: decoder)
        }
    }
}

// MARK: - Store

@MainActor
final class TeamParityStore: ObservableObject {
    static let shared = TeamParityStore()

    nonisolated static var typingThrottle: TimeInterval { 3 }
    nonisolated static var typingVisibleFor: TimeInterval { 6 }
    static let quickReactions = ["\u{1F44D}", "\u{2764}\u{FE0F}", "\u{1F602}", "\u{1F389}", "\u{1F440}", "\u{2705}"]

    /// channel id -> user id -> when their last typing event arrived.
    @Published private(set) var typing: [String: [String: Date]] = [:]
    @Published private(set) var pins: [TeamMessage] = []
    @Published private(set) var searchResults: [TeamMessage] = []
    @Published private(set) var reads: [TeamChannelRead] = []
    @Published var lastError: String?

    private var lastTypingSent: [String: Date] = [:]

    // Pure helpers (tested).

    nonisolated static func shouldSendTyping(lastSent: Date?, now: Date, interval: TimeInterval = typingThrottle) -> Bool {
        guard let lastSent else { return true }
        return now.timeIntervalSince(lastSent) >= interval
    }

    nonisolated static func activeTypers(_ seen: [String: Date], now: Date, excluding me: String?,
                                         window: TimeInterval = typingVisibleFor) -> [String] {
        seen.filter { $0.key != me && now.timeIntervalSince($0.value) < window }.keys.sorted()
    }

    nonisolated static func merged(_ reactions: [TeamReaction]) -> [TeamReaction] {
        var order: [String] = []
        var rows: [String: TeamReaction] = [:]
        for reaction in reactions {
            if let existing = rows[reaction.emoji] {
                let ids = Array(Set(existing.user_ids + reaction.user_ids)).sorted()
                rows[reaction.emoji] = TeamReaction(emoji: reaction.emoji,
                                                    count: max(existing.count + reaction.count, ids.count),
                                                    user_ids: ids)
            } else {
                order.append(reaction.emoji)
                rows[reaction.emoji] = reaction
            }
        }
        return order.compactMap { rows[$0] }
    }

    /// Who, apart from the sender, has read up to `message`.
    nonisolated static func seenBy(_ message: TeamMessage, reads: [TeamChannelRead]) -> [TeamChannelRead] {
        let sent = TeamLossy.date(message.created_at)
        return reads.filter { read in
            guard read.user_id != message.sender_id else { return false }
            if read.message_id == message.id { return true }
            guard let sent, let at = TeamLossy.date(read.read_at) else { return false }
            return at >= sent
        }
    }

    nonisolated static func pathSegment(_ raw: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }

    nonisolated static func queryValue(_ raw: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }

    nonisolated static func messagePath(channelId: String, messageId: String) -> String {
        "/team/channels/\(pathSegment(channelId))/messages/\(pathSegment(messageId))"
    }

    nonisolated static func channelPath(_ channelId: String) -> String {
        "/team/channels/\(pathSegment(channelId))"
    }

    // Network.

    private func call(_ path: String, method: String = "GET", json: [String: Any]? = nil) async throws -> Data {
        var body: Data?
        if let json { body = try JSONSerialization.data(withJSONObject: json) }
        let req = try APIClient.shared.makeRequest(path: path, method: method, body: body)
        return try await APIClient.shared.makeAuthorizedRequest(req)
    }

    private func reload(_ channelId: String) async {
        if TeamStore.shared.activeId == channelId { await TeamStore.shared.open(channelId) }
    }

    func edit(channelId: String, messageId: String, body: String) async -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            _ = try await call(Self.messagePath(channelId: channelId, messageId: messageId), method: "PATCH", json: ["body": trimmed])
            await reload(channelId)
            return true
        } catch {
            lastError = "Could not edit that message."
            return false
        }
    }

    func delete(channelId: String, messageId: String) async {
        do {
            _ = try await call(Self.messagePath(channelId: channelId, messageId: messageId), method: "DELETE")
            await reload(channelId)
        } catch {
            lastError = "Could not delete that message."
        }
    }

    func react(channelId: String, messageId: String, emoji: String) async {
        do {
            _ = try await call(Self.messagePath(channelId: channelId, messageId: messageId) + "/reactions",
                               method: "POST", json: ["emoji": emoji])
            await reload(channelId)
        } catch {
            lastError = "Could not add that reaction."
        }
    }

    func unreact(channelId: String, messageId: String, emoji: String) async {
        do {
            _ = try await call(Self.messagePath(channelId: channelId, messageId: messageId)
                               + "/reactions?emoji=" + Self.queryValue(emoji), method: "DELETE")
            await reload(channelId)
        } catch {
            lastError = "Could not remove that reaction."
        }
    }

    /// Adds my reaction, or removes it when I already reacted with that emoji.
    func toggleReaction(channelId: String, message: TeamMessage, emoji: String, myId: String?) async {
        let mine = (message.reactions ?? []).first { $0.emoji == emoji }?.user_ids.contains { $0 == myId } ?? false
        if mine {
            await unreact(channelId: channelId, messageId: message.id, emoji: emoji)
        } else {
            await react(channelId: channelId, messageId: message.id, emoji: emoji)
        }
    }

    func togglePin(channelId: String, messageId: String) async {
        do {
            _ = try await call(Self.messagePath(channelId: channelId, messageId: messageId) + "/pin", method: "POST")
            await reload(channelId)
            await loadPins(channelId)
        } catch {
            lastError = "Could not pin that message."
        }
    }

    func loadPins(_ channelId: String) async {
        guard let data = try? await call(Self.channelPath(channelId) + "/pins") else {
            pins = []
            return
        }
        pins = TeamLossy.list(TeamPinEntry.self, from: data, keys: ["pins", "messages", "items"]).map { $0.message }
    }

    func search(_ channelId: String, query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        guard let data = try? await call(Self.channelPath(channelId) + "/search?q=" + Self.queryValue(trimmed)) else {
            searchResults = []
            lastError = "Search failed."
            return
        }
        searchResults = TeamLossy.list(TeamMessage.self, from: data, keys: ["messages", "results", "hits", "items"])
    }

    func loadReads(_ channelId: String) async {
        guard let data = try? await call(Self.channelPath(channelId) + "/reads") else {
            reads = []
            return
        }
        reads = TeamLossy.list(TeamChannelRead.self, from: data, keys: ["reads", "items", "members"])
    }

    // Typing.

    /// Called as the draft changes. Posts at most once every 3 s per channel.
    func userTyped(in channelId: String, draft: String, now: Date = Date()) {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard Self.shouldSendTyping(lastSent: lastTypingSent[channelId], now: now) else { return }
        lastTypingSent[channelId] = now
        Task { _ = try? await call(Self.channelPath(channelId) + "/typing", method: "POST") }
    }

    /// A {type: "typing"} event from the team websocket.
    func handleTypingEvent(_ obj: [String: Any], now: Date = Date()) {
        guard let channelId = Self.text(obj["channel_id"]) ?? Self.text(obj["channelId"]),
              let userId = Self.text(obj["user_id"]) ?? Self.text(obj["userId"]) else { return }
        if (obj["stopped"] as? Bool) == true || (obj["typing"] as? Bool) == false {
            typing[channelId]?[userId] = nil
        } else {
            typing[channelId, default: [:]][userId] = now
        }
        // Let the indicator lapse without another event.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.typingVisibleFor * 1_000_000_000))
            self?.expireTyping()
        }
    }

    /// A message from someone ends their typing indicator.
    func clearTyping(channelId: String, userId: String?) {
        guard let userId else { return }
        typing[channelId]?[userId] = nil
    }

    func typers(in channelId: String, me: String?, now: Date = Date()) -> [String] {
        Self.activeTypers(typing[channelId] ?? [:], now: now, excluding: me)
    }

    private func expireTyping(now: Date = Date()) {
        var next: [String: [String: Date]] = [:]
        for (channel, seen) in typing {
            let live = seen.filter { now.timeIntervalSince($0.value) < Self.typingVisibleFor }
            if !live.isEmpty { next[channel] = live }
        }
        if next != typing { typing = next }
    }

    private static func text(_ value: Any?) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        if let n = value as? Int { return String(n) }
        return nil
    }
}

// MARK: - Views

struct TeamReactionsRow: View {
    let channelId: String
    let message: TeamMessage
    @ObservedObject private var parity = TeamParityStore.shared
    @ObservedObject private var store = TeamStore.shared

    var body: some View {
        let reactions = message.reactions ?? []
        if !reactions.isEmpty {
            HStack(spacing: 6) {
                ForEach(reactions, id: \.emoji) { reaction in
                    let mine = reaction.user_ids.contains { $0 == store.myId }
                    Button {
                        Task { await parity.toggleReaction(channelId: channelId, message: message, emoji: reaction.emoji, myId: store.myId) }
                    } label: {
                        Text("\(reaction.emoji) \(reaction.count)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(mine ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15)))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(reaction.emoji) \(reaction.count)\(mine ? ", you reacted" : "")")
                }
            }
        }
    }
}

/// The long-press menu items added in v789.
struct TeamMessageParityMenu: View {
    let channelId: String
    let message: TeamMessage
    let mine: Bool
    @Binding var editTarget: TeamMessage?
    @Binding var deleteTarget: TeamMessage?
    @Binding var seenTarget: TeamMessage?
    @ObservedObject private var parity = TeamParityStore.shared
    @ObservedObject private var store = TeamStore.shared

    var body: some View {
        if message.deleted_at == nil {
            Menu {
                ForEach(TeamParityStore.quickReactions, id: \.self) { emoji in
                    Button(emoji) {
                        Task { await parity.toggleReaction(channelId: channelId, message: message, emoji: emoji, myId: store.myId) }
                    }
                }
            } label: { Label("React", systemImage: "face.smiling") }
            Button {
                Task { await parity.togglePin(channelId: channelId, messageId: message.id) }
            } label: {
                Label((message.pinned ?? false) ? "Unpin" : "Pin to conversation",
                      systemImage: (message.pinned ?? false) ? "pin.slash" : "pin")
            }
        }
        Button { seenTarget = message } label: { Label("Seen by", systemImage: "eye") }
        if mine && message.deleted_at == nil {
            Button { editTarget = message } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { deleteTarget = message } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

/// Under a message: (edited), pinned, and the reactions.
struct TeamMessageParityFooter: View {
    let channelId: String
    let message: TeamMessage

    var body: some View {
        if message.edited_at != nil && message.deleted_at == nil {
            Text("(edited)").font(.caption2).foregroundColor(.secondary)
        }
        if message.pinned ?? false {
            Label("Pinned", systemImage: "pin.fill").font(.caption2).foregroundColor(.orange)
        }
        TeamReactionsRow(channelId: channelId, message: message)
    }
}

/// The sheets, delete confirmation and error alert TeamChannelView gained in v789.
struct TeamChannelParitySheets: ViewModifier {
    let channelId: String
    @Binding var editTarget: TeamMessage?
    @Binding var deleteTarget: TeamMessage?
    @Binding var seenTarget: TeamMessage?
    @Binding var showPins: Bool
    @Binding var showChannelSearch: Bool
    @Binding var showSeenBy: Bool
    @ObservedObject private var parity = TeamParityStore.shared

    private var confirmingDelete: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private var showingError: Binding<Bool> {
        Binding(get: { parity.lastError != nil }, set: { if !$0 { parity.lastError = nil } })
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $editTarget) { message in TeamEditMessageSheet(channelId: channelId, message: message) }
            .sheet(item: $seenTarget) { message in TeamSeenByView(channelId: channelId, message: message) }
            .sheet(isPresented: $showPins) { TeamPinnedView(channelId: channelId) }
            .sheet(isPresented: $showChannelSearch) { TeamChannelSearchView(channelId: channelId) }
            .sheet(isPresented: $showSeenBy) { TeamSeenByView(channelId: channelId) }
            .confirmationDialog("Delete this message?", isPresented: confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteNow() }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            }
            .alert("Team chat", isPresented: showingError) {
                Button("OK", role: .cancel) { parity.lastError = nil }
            } message: {
                Text(parity.lastError ?? "")
            }
    }

    private func deleteNow() {
        guard let target = deleteTarget else { return }
        deleteTarget = nil
        Task { await TeamParityStore.shared.delete(channelId: channelId, messageId: target.id) }
    }
}

struct TeamTypingLine: View {
    let channelId: String
    @ObservedObject private var parity = TeamParityStore.shared
    @ObservedObject private var store = TeamStore.shared

    var body: some View {
        let names = parity.typers(in: channelId, me: store.myId).map { store.name(for: $0) }
        if !names.isEmpty {
            Text(names.count == 1 ? "\(names[0]) is typing..." : "\(names.joined(separator: ", ")) are typing...")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 4)
        }
    }
}

struct TeamEditMessageSheet: View {
    let channelId: String
    let message: TeamMessage
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var saving = false

    init(channelId: String, message: TeamMessage) {
        self.channelId = channelId
        self.message = message
        _draft = State(initialValue: message.body)
    }

    var body: some View {
        NavigationView {
            Form {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(3...10)
            }
            .navigationTitle("Edit message")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button(saving ? "Saving..." : "Save") {
                    saving = true
                    Task {
                        let ok = await TeamParityStore.shared.edit(channelId: channelId, messageId: message.id, body: draft)
                        saving = false
                        if ok { dismiss() }
                    }
                }
                .disabled(saving || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft == message.body)
            )
        }
        .navigationViewStyle(.stack)
    }
}

struct TeamPinnedView: View {
    let channelId: String
    @ObservedObject private var parity = TeamParityStore.shared
    @ObservedObject private var store = TeamStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if parity.pins.isEmpty {
                    Text("Nothing is pinned in this conversation.").foregroundColor(.secondary)
                }
                ForEach(parity.pins) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.bot ?? store.name(for: message.sender_id)).font(.caption).foregroundColor(.secondary)
                        TeamFormattedText(text: message.body)
                    }
                    .swipeActions {
                        Button("Unpin") { Task { await parity.togglePin(channelId: channelId, messageId: message.id) } }
                            .tint(.orange)
                    }
                }
            }
            .navigationTitle("Pinned")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
        .navigationViewStyle(.stack)
        .task { await parity.loadPins(channelId) }
    }
}

struct TeamChannelSearchView: View {
    let channelId: String
    @ObservedObject private var parity = TeamParityStore.shared
    @ObservedObject private var store = TeamStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationView {
            List {
                ForEach(parity.searchResults) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(message.bot ?? store.name(for: message.sender_id)).font(.caption).foregroundColor(.secondary)
                            Spacer()
                            if let at = message.created_at {
                                Text(DialerDashboardStore.time(TeamLossy.date(at))).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        TeamFormattedText(text: message.body)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search this conversation")
            .onSubmit(of: .search) { Task { await parity.search(channelId, query: query) } }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
        .navigationViewStyle(.stack)
    }
}

/// Who has read the conversation, or (with `message`) who has seen that message.
struct TeamSeenByView: View {
    let channelId: String
    var message: TeamMessage? = nil
    @ObservedObject private var parity = TeamParityStore.shared
    @ObservedObject private var store = TeamStore.shared
    @Environment(\.dismiss) private var dismiss

    private var rows: [TeamChannelRead] {
        let all = parity.reads.filter { $0.user_id != store.myId }
        guard let message else { return all }
        return TeamParityStore.seenBy(message, reads: all)
    }

    var body: some View {
        NavigationView {
            List {
                if rows.isEmpty {
                    Text(message == nil ? "Nobody has read this conversation yet." : "Nobody has seen this message yet.")
                        .foregroundColor(.secondary)
                }
                ForEach(rows) { read in
                    HStack {
                        Text(store.name(for: read.user_id))
                        Spacer()
                        Text(DialerDashboardStore.time(TeamLossy.date(read.read_at))).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Seen by")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
        .navigationViewStyle(.stack)
        .task { await parity.loadReads(channelId) }
    }
}
