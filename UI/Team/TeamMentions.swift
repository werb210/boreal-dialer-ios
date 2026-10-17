// BOREAL_DIALER_v803_MENTIONS - @mentions in Team chat, matching the portal
// (BF-portal CommunicationsPage onDraftChange / pickMention / send):
//  - typing "@" in a composer lists the conversation's members;
//  - picking one inserts "@Full Name " and remembers that user's id;
//  - on send, "mentions": [userId, ...] carries only the ids whose "@Name" is
//    still in the text (POST /team/channels/:id/messages and thread replies);
//  - @Name tokens render highlighted;
//  - a live message that mentions me, in a conversation not on screen, raises a
//    local notification "<Sender> mentioned you".
import Foundation
import SwiftUI
import UserNotifications

enum TeamMentionDraft {
    // The portal's /@([\w.'-]*)$/ - a mention being typed at the end of the draft.
    private static let trailing = try? NSRegularExpression(pattern: #"@([\w.'-]*)$"#)

    /// The partial name typed after a trailing "@" ("" right after the @), or nil
    /// when the end of the draft is not a mention in progress.
    static func query(in draft: String) -> String? {
        guard let regex = trailing else { return nil }
        let range = NSRange(draft.startIndex..<draft.endIndex, in: draft)
        guard let match = regex.firstMatch(in: draft, range: range),
              let captured = Range(match.range(at: 1), in: draft) else { return nil }
        return String(draft[captured])
    }

    /// Replaces the trailing "@partial" with "@Full Name ".
    static func insert(name: String, into draft: String) -> String {
        guard let regex = trailing else { return draft + "@" + name + " " }
        let range = NSRange(draft.startIndex..<draft.endIndex, in: draft)
        guard let match = regex.firstMatch(in: draft, range: range),
              let whole = Range(match.range, in: draft) else { return draft + "@" + name + " " }
        return draft.replacingCharacters(in: whole, with: "@" + name + " ")
    }

    /// Ids to send: picked ids whose "@Name" is still present, without duplicates.
    static func outgoing(ids: [String], draft: String, name: (String) -> String) -> [String] {
        var out: [String] = []
        for id in ids where !out.contains(id) && draft.contains("@" + name(id)) {
            out.append(id)
        }
        return out
    }

    /// Who can be mentioned: the conversation's members (everyone when the
    /// member list is unknown), minus me, filtered by the typed prefix.
    static func candidates(users: [TeamUser], memberIds: [String], me: String?, query: String) -> [TeamUser] {
        let q = query.lowercased()
        let pool = memberIds.isEmpty ? users : users.filter { memberIds.contains($0.id) }
        return pool.filter { user in
            if let me, user.id == me { return false }
            if let email = user.email?.lowercased(), email.hasSuffix("@system.local") { return false }
            if q.isEmpty { return true }
            let name = user.name.lowercased()
            return name.hasPrefix(q) || name.contains(" " + q)
        }
    }
}

enum TeamMentionFormat {
    /// Makes every "@Name" (for a known name) bold and bright green.
    static func highlight(_ source: AttributedString, names: [String]) -> AttributedString {
        let tokens = Array(Set(names.filter { !$0.isEmpty })).sorted { $0.count > $1.count }
        guard !tokens.isEmpty else { return source }
        var out = source
        for name in tokens {
            let token = "@" + name
            var start = out.startIndex
            while start < out.endIndex, let found = out[start..<out.endIndex].range(of: token) {
                out[found][AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Theme.greenBright
                out[found][AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute.self] = .stronglyEmphasized
                start = found.upperBound
            }
        }
        return out
    }
}

enum TeamMentionAlert {
    /// Posts "<Sender> mentioned you" now, only when notifications are allowed.
    static func post(sender: String, body: String, channelId: String?, messageId: String) {
        let title = sender + " mentioned you"
        let text = body.isEmpty ? "New message in Team chat" : body
        let channel = channelId ?? ""
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed: [UNAuthorizationStatus] = [.authorized, .provisional, .ephemeral]
            guard allowed.contains(settings.authorizationStatus) else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = text
            content.sound = .default
            content.threadIdentifier = "team-" + channel
            content.userInfo = ["type": "team_mention", "channelId": channel]
            FocusAlertPolicy.tag(content, as: .internalStaff) // BOREAL_DIALER_v821 - held back by the client-only Focus
            let request = UNNotificationRequest(identifier: "team-mention-" + messageId, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }
}

/// The member list shown above a Team composer while an @mention is being typed.
struct TeamMentionSuggestions: View {
    let users: [TeamUser]
    let onPick: (TeamUser) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(users.prefix(8)) { user in
                    Button {
                        onPick(user)
                    } label: {
                        HStack(spacing: 10) {
                            AvatarCircle(name: user.name, size: 28)
                            Text("@" + user.name)
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundColor(Theme.text)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mention \(user.name)")
                }
            }
        }
        .frame(maxHeight: 200)
        .background(Theme.surface2)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}
