// BOREAL_DIALER_TEAM_PHASE_B_v667 - Team chat on the iPhone catches up with the portal.
// Phase A: mute a conversation, mark unread from a message, your status (text, emoji, clear
// after, Do Not Disturb), everyone's status next to their name, and Away while the app is in
// the background. Phase B: browse / join / leave channels, topic and privacy, add people,
// archive, threads, search every conversation, and message formatting (bold, italic, strike,
// code, code blocks, lists). Server: BF-Server v643 (prefs) and v658/v659 (Phase B).
import Foundation
import SwiftUI
import UIKit

struct TeamThreadSummary: Decodable, Equatable {
    let reply_count: Int
    let last_reply_at: String?
    let participant_ids: [String]?
}

struct TeamStatusRow: Decodable, Equatable {
    let user_id: String
    let status_text: String?
    let status_emoji: String?
    let status_until: String?
    let dnd: Bool
    let dnd_until: String?
    let away: Bool
}

struct TeamBrowseRow: Identifiable, Decodable {
    let id: String
    let name: String?
    let topic: String?
    let is_private: Bool?
    let archived_at: String?
    let member_count: Int
    let is_member: Bool
}

struct TeamSearchHit: Identifiable, Decodable {
    let id: String
    let channel_id: String
    let sender_id: String?
    let body: String
    let created_at: String?
    let thread_root_id: String?
    let channel_kind: String?
    let channel_name: String?
    let files: [String]?
}

/// Where the Team tab should navigate: a conversation, optionally straight into a thread.
struct TeamOpenTarget: Equatable {
    let channelId: String
    let title: String
    let threadRootId: String?
}

// MARK: - Formatting

enum TeamBlock: Equatable {
    case line(String)
    case code(String)
}

enum TeamFormat {
    /// Message text -> display blocks: fenced code, bullets shown as dots, everything else as lines.
    static func blocks(_ text: String) -> [TeamBlock] {
        let fence = String(repeating: "\u{60}", count: 3)
        var out: [TeamBlock] = []
        var code: [String] = []
        var inCode = false
        for raw in text.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if inCode {
                if trimmed.hasSuffix(fence) {
                    let tail = String(trimmed.dropLast(3))
                    if !tail.isEmpty { code.append(tail) }
                    out.append(.code(code.joined(separator: "\n")))
                    code = []
                    inCode = false
                } else {
                    code.append(raw)
                }
                continue
            }
            if trimmed.hasPrefix(fence) {
                let rest = String(trimmed.dropFirst(3))
                if rest.count >= 3 && rest.hasSuffix(fence) {
                    out.append(.code(String(rest.dropLast(3))))
                } else {
                    inCode = true
                    if !rest.isEmpty { code.append(rest) }
                }
                continue
            }
            if let bullet = ["- ", "* ", "\u{2022} "].first(where: { trimmed.hasPrefix($0) }) {
                out.append(.line("\u{2022} " + String(trimmed.dropFirst(bullet.count))))
                continue
            }
            out.append(.line(raw))
        }
        if inCode { out.append(.code(code.joined(separator: "\n"))) }
        return out
    }

    /// The portal writes strikethrough as ~text~; Apple's Markdown wants ~~text~~.
    static func markdownSource(_ line: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!~)~([^~\s][^~]*?)~(?!~)"#) else { return line }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.stringByReplacingMatches(in: line, range: range, withTemplate: "~~$1~~")
    }

    static func attributed(_ line: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: markdownSource(line), options: options) {
            return parsed
        }
        return AttributedString(line)
    }
}

struct TeamFormattedText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(TeamFormat.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let code):
                    Text(code)
                        .font(.system(.callout, design: .monospaced))
                        .padding(6)
                        .background(Color.black.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                case .line(let line):
                    Text(TeamFormat.attributed(line))
                }
            }
        }
    }
}

// MARK: - Store

@MainActor
final class TeamPhaseBStore: ObservableObject {
    static let shared = TeamPhaseBStore()

    @Published var statuses: [String: TeamStatusRow] = [:]
    @Published var threadRoot: TeamMessage?
    @Published var threadReplies: [TeamMessage] = []
    @Published var threadMissing = false
    @Published var lastError: String?
    private var threadKey: String?
    private var observers: [NSObjectProtocol] = []

    private func call(_ path: String, method: String = "GET", json: [String: Any]? = nil) async throws -> Data {
        var body: Data?
        if let json { body = try JSONSerialization.data(withJSONObject: json) }
        let req = try APIClient.shared.makeRequest(path: path, method: method, body: body)
        return try await APIClient.shared.makeAuthorizedRequest(req)
    }

    // Status

    func loadStatuses() async {
        struct Resp: Decodable { let statuses: [TeamStatusRow] }
        guard let data = try? await call("/team/statuses"),
              let rows = try? JSONDecoder().decode(Resp.self, from: data).statuses else { return }
        statuses = Dictionary(rows.map { ($0.user_id, $0) }, uniquingKeysWith: { _, b in b })
    }

    func statusLine(for userId: String) -> String? {
        guard let s = statuses[userId] else { return nil }
        var parts: [String] = []
        if s.dnd { parts.append("\u{1F319}") }
        if let e = s.status_emoji, !e.isEmpty { parts.append(e) }
        if let t = s.status_text, !t.isEmpty { parts.append(t) } else if s.dnd { parts.append("Do not disturb") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    func isAway(_ userId: String) -> Bool { statuses[userId]?.away ?? false }

    /// clearAfter: "never", "1h", "4h", "today". dnd: "keep", "off", "1h", "tomorrow8".
    func saveStatus(text: String, emoji: String, clearAfter: String, dnd: String) async -> Bool {
        var json: [String: Any] = [
            "status_text": text.isEmpty ? NSNull() as Any : text as Any,
            "status_emoji": emoji.isEmpty ? NSNull() as Any : emoji as Any,
            "status_until": Self.until(clearAfter).map { $0 as Any } ?? NSNull() as Any,
        ]
        if dnd != "keep" { json["dnd_until"] = Self.until(dnd).map { $0 as Any } ?? NSNull() as Any }
        return await putStatus(json)
    }

    func clearStatus() async -> Bool {
        await putStatus(["status_text": NSNull(), "status_emoji": NSNull(), "status_until": NSNull(), "dnd_until": NSNull()])
    }

    func setAway(_ away: Bool) async { _ = await putStatus(["away": away]) }

    private func putStatus(_ json: [String: Any]) async -> Bool {
        struct Resp: Decodable { let status: TeamStatusRow? }
        do {
            let data = try await call("/team/status", method: "PUT", json: json)
            if let row = try? JSONDecoder().decode(Resp.self, from: data).status { statuses[row.user_id] = row }
            return true
        } catch {
            return false
        }
    }

    nonisolated static func until(_ choice: String, now: Date = Date()) -> String? {
        let iso = ISO8601DateFormatter()
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        switch choice {
        case "1h": return iso.string(from: now.addingTimeInterval(3600))
        case "4h": return iso.string(from: now.addingTimeInterval(4 * 3600))
        case "today":
            return cal.date(bySettingHour: 23, minute: 59, second: 0, of: now).map { iso.string(from: $0) }
        case "tomorrow8":
            guard let tomorrow = cal.date(byAdding: .day, value: 1, to: now) else { return nil }
            return cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow).map { iso.string(from: $0) }
        default: return nil
        }
    }

    /// Away while the app is in the background, back when it returns (the portal does the same on idle).
    func startIdleAway() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await TeamPhaseBStore.shared.setAway(true) }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await TeamPhaseBStore.shared.setAway(false) }
        })
    }

    // Conversation actions

    func setMuted(_ channelId: String, muted: Bool) async {
        _ = try? await call("/team/channels/\(channelId)/mute", method: "POST", json: ["muted": muted])
        await TeamStore.shared.loadChannels()
    }

    func markUnread(_ channelId: String, messageId: String) async {
        _ = try? await call("/team/channels/\(channelId)/unread", method: "POST", json: ["message_id": messageId])
        await TeamStore.shared.loadChannels()
    }

    func browse() async -> [TeamBrowseRow] {
        struct Resp: Decodable { let channels: [TeamBrowseRow] }
        guard let data = try? await call("/team/channels/browse") else { return [] }
        return (try? JSONDecoder().decode(Resp.self, from: data).channels) ?? []
    }

    func join(_ channelId: String) async -> Bool {
        do {
            _ = try await call("/team/channels/\(channelId)/join", method: "POST", json: [:])
            await TeamStore.shared.loadChannels()
            return true
        } catch {
            return false
        }
    }

    func leave(_ channelId: String) async -> Bool {
        do {
            _ = try await call("/team/channels/\(channelId)/leave", method: "POST", json: [:])
            await TeamStore.shared.loadChannels()
            return true
        } catch {
            return false
        }
    }

    func update(_ channelId: String, name: String, topic: String, isPrivate: Bool?) async -> Bool {
        var json: [String: Any] = ["name": name, "topic": topic]
        if let isPrivate { json["is_private"] = isPrivate }
        do {
            _ = try await call("/team/channels/\(channelId)", method: "PATCH", json: json)
            await TeamStore.shared.loadChannels()
            return true
        } catch {
            return false
        }
    }

    func setArchived(_ channelId: String, archived: Bool) async -> Bool {
        do {
            _ = try await call("/team/channels/\(channelId)/archive", method: "POST", json: ["archived": archived])
            await TeamStore.shared.loadChannels()
            return true
        } catch {
            return false
        }
    }

    func addMembers(_ channelId: String, ids: [String]) async -> Bool {
        do {
            _ = try await call("/team/channels/\(channelId)/members", method: "POST", json: ["member_ids": ids])
            await TeamStore.shared.loadChannels()
            return true
        } catch {
            return false
        }
    }

    func search(_ query: String) async -> [TeamSearchHit] {
        struct Resp: Decodable { let messages: [TeamSearchHit] }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let data = try? await call("/team/search?q=\(encoded)") else { return [] }
        return (try? JSONDecoder().decode(Resp.self, from: data).messages) ?? []
    }

    // Threads

    func loadThread(channelId: String, rootId: String) async {
        struct Resp: Decodable { let root: TeamMessage; let replies: [TeamMessage] }
        threadKey = rootId
        threadRoot = nil
        threadReplies = []
        threadMissing = false
        guard let data = try? await call("/team/channels/\(channelId)/threads/\(rootId)"),
              let resp = try? JSONDecoder().decode(Resp.self, from: data) else {
            threadMissing = true
            return
        }
        guard threadKey == rootId else { return }
        threadRoot = resp.root
        threadReplies = resp.replies
    }

    func reply(channelId: String, rootId: String, body: String) async -> Bool {
        struct Resp: Decodable { let message: TeamMessage }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        do {
            let data = try await call("/team/channels/\(channelId)/threads/\(rootId)/messages", method: "POST", json: ["body": text])
            let message = try JSONDecoder().decode(Resp.self, from: data).message
            if threadKey == rootId && !threadReplies.contains(where: { $0.id == message.id }) { threadReplies.append(message) }
            return true
        } catch {
            return false
        }
    }

    /// Socket events the Team store forwards: live thread replies and status changes.
    func handleSocket(_ obj: [String: Any]) {
        let type = obj["type"] as? String
        if type == "thread_message", let rootId = obj["root_id"] as? String, rootId == threadKey,
           let raw = obj["message"], let data = try? JSONSerialization.data(withJSONObject: raw),
           let message = try? JSONDecoder().decode(TeamMessage.self, from: data),
           !threadReplies.contains(where: { $0.id == message.id }) {
            threadReplies.append(message)
        } else if type == "status", let raw = obj["status"], let data = try? JSONSerialization.data(withJSONObject: raw),
                  let row = try? JSONDecoder().decode(TeamStatusRow.self, from: data) {
            statuses[row.user_id] = row
        }
    }
}
