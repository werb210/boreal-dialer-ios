// BOREAL_DIALER_TEAM_PHASE_C_v673 - Team chat Phase C on the iPhone, matching the portal: deal and
// contact cards for links in messages, posts from Boreal and Maya shown under their name, Save for
// later / Remind me, the Saved list, a call button in direct messages, and in-app reminders.
// Server: BF-Server v671.
import Foundation
import SwiftUI
import UserNotifications

struct TeamCard: Identifiable, Decodable, Equatable {
    let kind: String
    let id: String
    let title: String
    let subtitle: String?
    let url: String
}

struct TeamSavedRow: Identifiable, Decodable {
    var id: String { message_id }
    let message_id: String
    let channel_id: String
    let thread_root_id: String?
    let body: String
    let bot: String?
    let sender_id: String?
    let remind_at: String?
    let reminded_at: String?
    let channel_kind: String?
    let channel_name: String?
}

enum TeamCardRefs {
    /// "contact:<id>" / "application:<id>" for portal links in a message, in order, at most five.
    static func keys(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"/(crm/contacts|contacts|applications)/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})"#) else { return [] }
        var out: [String] = []
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            guard let kindRange = Range(match.range(at: 1), in: text), let idRange = Range(match.range(at: 2), in: text) else { continue }
            let key = (text[kindRange] == "applications" ? "application:" : "contact:") + text[idRange].lowercased()
            if !out.contains(key) { out.append(key) }
            if out.count >= 5 { break }
        }
        return out
    }

    /// When a "Remind me" choice fires, as ISO 8601 (nil = save without a reminder).
    static func remindAt(_ choice: String, now: Date = Date()) -> String? {
        let iso = ISO8601DateFormatter()
        switch choice {
        case "1h": return iso.string(from: now.addingTimeInterval(3600))
        case "3h": return iso.string(from: now.addingTimeInterval(3 * 3600))
        case "tomorrow":
            let cal = Calendar.current
            guard let tomorrow = cal.date(byAdding: .day, value: 1, to: now),
                  let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) else { return nil }
            return iso.string(from: nine)
        default: return nil
        }
    }
}

@MainActor
final class TeamPhaseCStore: ObservableObject {
    static let shared = TeamPhaseCStore()
    @Published var cards: [String: TeamCard] = [:]
    @Published var saved: [TeamSavedRow] = []
    @Published var toast: String?
    private var asked: Set<String> = []

    private func call(_ path: String, method: String = "GET", json: [String: Any]? = nil) async throws -> Data {
        var body: Data?
        if let json { body = try JSONSerialization.data(withJSONObject: json) }
        let req = try APIClient.shared.makeRequest(path: path, method: method, body: body)
        return try await APIClient.shared.makeAuthorizedRequest(req)
    }

    func loadCards(_ keys: [String]) async {
        struct Resp: Decodable { let cards: [TeamCard] }
        let missing = keys.filter { !asked.contains($0) }
        guard !missing.isEmpty else { return }
        missing.forEach { asked.insert($0) }
        guard let data = try? await call("/team/cards?ids=" + missing.joined(separator: ",")),
              let resp = try? JSONDecoder().decode(Resp.self, from: data) else { return }
        for card in resp.cards { cards[card.kind + ":" + card.id] = card }
    }

    func save(_ messageId: String, choice: String) async {
        let when = TeamCardRefs.remindAt(choice)
        do {
            _ = try await call("/team/messages/\(messageId)/save", method: "POST", json: ["remind_at": when.map { $0 as Any } ?? NSNull() as Any])
            show(when == nil ? "Saved for later" : "Reminder set")
        } catch {
            show("Couldn't save")
        }
    }

    func unsave(_ messageId: String) async {
        _ = try? await call("/team/messages/\(messageId)/save", method: "DELETE")
        saved.removeAll { $0.message_id == messageId }
    }

    func loadSaved() async {
        struct Resp: Decodable { let saved: [TeamSavedRow] }
        guard let data = try? await call("/team/saved"), let resp = try? JSONDecoder().decode(Resp.self, from: data) else { return }
        saved = resp.saved
    }

    private func show(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self.toast == text { self.toast = nil }
        }
    }

    /// A reminder from the Team socket: show it as a notification now (push waits on the Apple account).
    func remind(body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Reminder"
        content.body = body.isEmpty ? "A saved Team message" : body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "team-reminder-" + UUID().uuidString, content: content, trigger: nil))
        show("Reminder: " + (body.isEmpty ? "saved message" : body))
    }
}

/// Cards for the contacts and applications linked in a message; tapping opens it in the portal.
struct TeamCardsView: View {
    let text: String
    @ObservedObject var store = TeamPhaseCStore.shared
    @Environment(\.openURL) var openURL

    var body: some View {
        let keys = TeamCardRefs.keys(in: text)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(keys.compactMap { store.cards[$0] }) { card in
                Button {
                    if let url = URL(string: "https://staff.boreal.financial" + card.url) { openURL(url) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: card.kind == "application" ? "briefcase.fill" : "person.crop.circle")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(card.title).font(.footnote.weight(.semibold)).lineLimit(1)
                            if let sub = card.subtitle, !sub.isEmpty {
                                Text(sub).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: keys.joined(separator: ",")) {
            if !keys.isEmpty { await store.loadCards(keys) }
        }
    }
}

struct TeamSavedView: View {
    let onOpen: (String, String, String?) -> Void
    @ObservedObject var store = TeamPhaseCStore.shared
    @ObservedObject var team = TeamStore.shared
    @Environment(\.dismiss) var dismiss

    func place(_ row: TeamSavedRow) -> String {
        if row.channel_kind == "channel", let name = row.channel_name { return "# " + name }
        return row.channel_name ?? "Direct message"
    }

    var body: some View {
        NavigationView {
            List {
                if store.saved.isEmpty {
                    Text("Nothing saved. Press and hold a message and choose Save for later.").foregroundColor(.secondary)
                }
                ForEach(store.saved) { row in
                    Button {
                        dismiss()
                        onOpen(row.channel_id, place(row), row.thread_root_id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place(row) + " \u{00B7} " + (row.bot ?? team.name(for: row.sender_id)) + (row.remind_at == nil ? "" : (row.reminded_at == nil ? " \u{00B7} \u{23F0}" : " \u{00B7} reminded")))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(row.body.isEmpty ? "Attachment" : row.body).foregroundColor(.primary).lineLimit(2)
                        }
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { Task { await store.unsave(row.message_id) } }
                    }
                }
            }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .task { await store.loadSaved() }
        }
        .navigationViewStyle(.stack)
    }
}
