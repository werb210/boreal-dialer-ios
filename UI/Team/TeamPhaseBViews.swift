// BOREAL_DIALER_TEAM_PHASE_B_v667 - screens for Team chat on the iPhone: a thread, channel details,
// browse channels, search every conversation, and your status. Stored properties are not private
// so TeamView.swift can create these screens.
import Foundation
import SwiftUI

struct TeamThreadView: View {
    let channelId: String
    let rootId: String
    let archived: Bool
    @ObservedObject var team = TeamStore.shared
    @ObservedObject var extras = TeamPhaseBStore.shared
    @State var draft = ""
    @State var sending = false

    func row(_ message: TeamMessage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(message.sender_id == team.myId ? "You" : team.name(for: message.sender_id))
                .font(.caption)
                .foregroundColor(.secondary)
            TeamFormattedText(text: message.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if extras.threadMissing {
                            Text("This thread is no longer available.").foregroundColor(.secondary)
                        }
                        if let root = extras.threadRoot {
                            row(root)
                            Text(extras.threadReplies.count == 1 ? "1 reply" : "\(extras.threadReplies.count) replies")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Divider()
                        }
                        ForEach(extras.threadReplies) { message in
                            row(message).id(message.id)
                        }
                        ThreadBottom()
                    }
                    .padding()
                }
                .onChange(of: extras.threadReplies.count) { _ in
                    withAnimation { proxy.scrollTo(ThreadBottom.id, anchor: .bottom) }
                }
            }
            Divider()
            HStack(alignment: .bottom) {
                TextField(archived ? "This channel is archived" : "Reply", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .disabled(archived)
                Button {
                    let text = draft
                    sending = true
                    Task {
                        if await extras.reply(channelId: channelId, rootId: rootId, body: text) { draft = "" }
                        sending = false
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(archived || sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(8)
        }
        .navigationTitle("Thread")
        .navigationBarTitleDisplayMode(.inline)
        .task { await extras.loadThread(channelId: channelId, rootId: rootId) }
    }
}

struct TeamChannelDetailsView: View {
    let channel: TeamChannel
    let onLeft: () -> Void
    @ObservedObject var team = TeamStore.shared
    @Environment(\.dismiss) var dismiss
    @State var name = ""
    @State var topic = ""
    @State var isPrivate = false
    @State var adding: Set<String> = []
    @State var message: String?
    @State var loaded = false

    var isChannel: Bool { channel.kind == "channel" }

    var body: some View {
        NavigationView {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Topic", text: $topic)
                    if isChannel {
                        Toggle("Private (only people who are added)", isOn: $isPrivate)
                    }
                    Button("Save") {
                        Task {
                            let ok = await TeamPhaseBStore.shared.update(channel.id, name: name, topic: topic, isPrivate: isChannel ? isPrivate : nil)
                            message = ok ? "Saved" : "Couldn't save. The name may already be taken."
                        }
                    }
                }
                Section("Members (\(channel.member_ids.count))") {
                    Text(channel.member_ids.map { team.name(for: $0) }.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    ForEach(team.users.filter { !channel.member_ids.contains($0.id) && $0.id != team.myId }) { user in
                        Button {
                            if adding.contains(user.id) { adding.remove(user.id) } else { adding.insert(user.id) }
                        } label: {
                            HStack {
                                Text(user.name).foregroundColor(.primary)
                                Spacer()
                                if adding.contains(user.id) {
                                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                    if !adding.isEmpty {
                        Button("Add \(adding.count)") {
                            Task {
                                let ok = await TeamPhaseBStore.shared.addMembers(channel.id, ids: Array(adding))
                                message = ok ? "Added" : "Couldn't add people."
                                if ok { adding.removeAll() }
                            }
                        }
                    }
                }
                Section {
                    if isChannel {
                        Button(channel.archived_at == nil ? "Archive channel" : "Unarchive channel") {
                            Task {
                                if await TeamPhaseBStore.shared.setArchived(channel.id, archived: channel.archived_at == nil) { dismiss() }
                            }
                        }
                    }
                    Button("Leave", role: .destructive) {
                        Task {
                            if await TeamPhaseBStore.shared.leave(channel.id) {
                                dismiss()
                                onLeft()
                            }
                        }
                    }
                }
                if let message {
                    Text(message).font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle(isChannel ? "Channel details" : "Group details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .onAppear {
                guard !loaded else { return }
                loaded = true
                name = channel.name ?? ""
                topic = channel.topic ?? ""
                isPrivate = channel.is_private ?? false
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct TeamBrowseView: View {
    let onOpen: (String, String) -> Void
    @Environment(\.dismiss) var dismiss
    @State var rows: [TeamBrowseRow] = []
    @State var query = ""
    @State var loading = true

    var shown: [TeamBrowseRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "#", with: "")
        guard !q.isEmpty else { return rows }
        return rows.filter { ($0.name ?? "").contains(q) || ($0.topic ?? "").lowercased().contains(q) }
    }

    var body: some View {
        NavigationView {
            List {
                if loading {
                    Text("Loading").foregroundColor(.secondary)
                }
                ForEach(shown) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(((row.is_private ?? false) ? "\u{1F512} " : "# ") + (row.name ?? "") + (row.archived_at == nil ? "" : " (archived)"))
                                .font(.system(size: 15.5, weight: .semibold))
                            Text("\(row.member_count) member\(row.member_count == 1 ? "" : "s")" + ((row.topic ?? "").isEmpty ? "" : " \u{00B7} " + (row.topic ?? "")))
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if row.is_member {
                            Button("Open") {
                                dismiss()
                                onOpen(row.id, "# " + (row.name ?? ""))
                            }
                            .buttonStyle(.bordered)
                        } else if row.archived_at == nil {
                            Button("Join") {
                                Task {
                                    if await TeamPhaseBStore.shared.join(row.id) {
                                        dismiss()
                                        onOpen(row.id, "# " + (row.name ?? ""))
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search channels")
            .navigationTitle("Browse channels")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .task {
                rows = await TeamPhaseBStore.shared.browse()
                loading = false
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct TeamSearchView: View {
    let onOpen: (String, String, String?) -> Void
    @ObservedObject var team = TeamStore.shared
    @Environment(\.dismiss) var dismiss
    @State var query = ""
    @State var hits: [TeamSearchHit] = []
    @State var searched = false

    func place(_ hit: TeamSearchHit) -> String {
        if hit.channel_kind == "channel", let name = hit.channel_name { return "# " + name }
        return hit.channel_name ?? "Direct message"
    }

    var body: some View {
        NavigationView {
            List {
                if searched && hits.isEmpty {
                    Text("Nothing found.").foregroundColor(.secondary)
                }
                ForEach(hits) { hit in
                    Button {
                        dismiss()
                        onOpen(hit.channel_id, place(hit), hit.thread_root_id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place(hit) + (hit.thread_root_id == nil ? "" : " \u{00B7} in a thread") + " \u{00B7} " + team.name(for: hit.sender_id))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(hit.body.isEmpty ? "\u{1F4CE} " + (hit.files ?? []).joined(separator: ", ") : hit.body)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search messages and files")
            .onSubmit(of: .search) {
                Task {
                    hits = await TeamPhaseBStore.shared.search(query)
                    searched = true
                }
            }
            .navigationTitle("Search Team")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
        .navigationViewStyle(.stack)
    }
}

struct TeamStatusView: View {
    @ObservedObject var extras = TeamPhaseBStore.shared
    @ObservedObject var team = TeamStore.shared
    @Environment(\.dismiss) var dismiss
    @State var text = ""
    @State var emoji = ""
    @State var clearAfter = "never"
    @State var dnd = "keep"
    @State var saving = false

    let presets: [(String, String)] = [("\u{1F4C5}", "In a meeting"), ("\u{1F697}", "Commuting"), ("\u{1F3E6}", "At lender meeting"), ("\u{1F334}", "Out of office")]

    var body: some View {
        NavigationView {
            Form {
                Section("Status") {
                    HStack {
                        TextField("\u{1F642}", text: $emoji).frame(width: 44)
                        TextField("What's your status?", text: $text)
                    }
                    ForEach(presets.indices, id: \.self) { index in
                        Button(presets[index].0 + " " + presets[index].1) {
                            emoji = presets[index].0
                            text = presets[index].1
                        }
                    }
                    Picker("Clear after", selection: $clearAfter) {
                        Text("Don't clear").tag("never")
                        Text("1 hour").tag("1h")
                        Text("4 hours").tag("4h")
                        Text("Today").tag("today")
                    }
                }
                Section("Do Not Disturb") {
                    Picker("Pause alerts", selection: $dnd) {
                        Text("Keep as is").tag("keep")
                        Text("Off").tag("off")
                        Text("For 1 hour").tag("1h")
                        Text("Until 8 am tomorrow").tag("tomorrow8")
                    }
                }
                Section {
                    Button("Save") {
                        saving = true
                        Task {
                            if await extras.saveStatus(text: text, emoji: emoji, clearAfter: clearAfter, dnd: dnd) { dismiss() }
                            saving = false
                        }
                    }
                    .disabled(saving)
                    Button("Clear status", role: .destructive) {
                        Task {
                            if await extras.clearStatus() { dismiss() }
                        }
                    }
                }
            }
            .navigationTitle("Your status")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .onAppear {
                if let me = team.myId, let s = extras.statuses[me] {
                    text = s.status_text ?? ""
                    emoji = s.status_emoji ?? ""
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
