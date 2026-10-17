// BOREAL_DIALER_v821 - quick replies: GET /templates/quick?channel=sms -> {items: [{id, name, body, isSnippet}]}.
// Compiled into the iPhone app and the Watch app (like the rest of Sources/WatchShared) so both order, cache and decode
// the list the same way. Merge fields stay in the body; BF-Server renders them when the text is sent.
import Foundation

/// BOREAL_DIALER_v821 - one quick reply.
public struct QuickReply: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let body: String
    public let isSnippet: Bool

    public init(id: String, name: String, body: String, isSnippet: Bool) {
        self.id = id
        self.name = name
        self.body = body
        self.isSnippet = isSnippet
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, body, isSnippet
        // The older template shapes (/templates and /watch/sms-templates) are accepted too.
        case bodyText = "body_text"
        case isSnippetSnake = "is_snippet"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? c.decode(String.self, forKey: .id) {
            id = text
        } else if let number = try? c.decode(Int.self, forKey: .id) {
            id = String(number)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "quick reply without an id")
        }
        let primary: String? = try? c.decodeIfPresent(String.self, forKey: .body)
        let legacy: String? = try? c.decodeIfPresent(String.self, forKey: .bodyText)
        let body = primary ?? legacy ?? ""
        self.body = body
        let rawName: String? = try? c.decodeIfPresent(String.self, forKey: .name)
        let name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = name.isEmpty ? String(body.prefix(32)) : name
        let snippet: Bool? = try? c.decodeIfPresent(Bool.self, forKey: .isSnippet)
        let snippetSnake: Bool? = try? c.decodeIfPresent(Bool.self, forKey: .isSnippetSnake)
        isSnippet = snippet ?? snippetSnake ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(body, forKey: .body)
        try c.encode(isSnippet, forKey: .isSnippet)
    }
}

/// BOREAL_DIALER_v821 - accepts {items}, {templates}, {data} or a bare array; one malformed row is skipped, not fatal.
public struct QuickReplyEnvelope: Decodable {
    public let items: [QuickReply]

    private enum CodingKeys: String, CodingKey { case items, templates, data }

    private struct Lossy: Decodable {
        let value: QuickReply?
        init(from decoder: Decoder) throws { value = try? QuickReply(from: decoder) }
    }

    public init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([Lossy].self) {
            items = array.compactMap(\.value)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let itemRows: [Lossy]? = try? c.decodeIfPresent([Lossy].self, forKey: .items)
        let templateRows: [Lossy]? = try? c.decodeIfPresent([Lossy].self, forKey: .templates)
        let dataRows: [Lossy]? = try? c.decodeIfPresent([Lossy].self, forKey: .data)
        guard let rows = itemRows ?? templateRows ?? dataRows else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no quick reply list"))
        }
        items = rows.compactMap(\.value)
    }
}

/// BOREAL_DIALER_v821 - snippets first, then templates; the server's order is kept inside each group (it is the order
/// staff arranged them in the portal). Empty bodies and repeated ids are dropped.
public enum QuickReplyOrdering {
    public static func ordered(_ items: [QuickReply]) -> [QuickReply] {
        var seen = Set<String>()
        let usable = items.filter { item in
            guard !item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return seen.insert(item.id).inserted
        }
        return usable.filter(\.isSnippet) + usable.filter { !$0.isSnippet }
    }

    public static func path(channel: String = "sms") -> String {
        "/templates/quick?channel=\(channel)"
    }
}

/// BOREAL_DIALER_v821 - the last list fetched, kept for a day so a reply on the wrist does not wait on the network.
public struct QuickReplyCache {
    public static let maxAge: TimeInterval = 24 * 60 * 60

    private struct Stored: Codable {
        let fetchedAt: Date
        let items: [QuickReply]
    }

    public let defaults: UserDefaults
    public let key: String

    public init(defaults: UserDefaults = .standard, key: String = "boreal.quickReplies.sms.v821") {
        self.defaults = defaults
        self.key = key
    }

    public static func isFresh(fetchedAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(fetchedAt)
        return age >= 0 && age < maxAge
    }

    /// The cached list (ordered) and whether it is still fresh.
    public func load(now: Date = Date()) -> (items: [QuickReply], fresh: Bool)? {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        return (QuickReplyOrdering.ordered(stored.items), Self.isFresh(fetchedAt: stored.fetchedAt, now: now))
    }

    public func store(_ items: [QuickReply], at date: Date = Date()) {
        guard let data = try? JSONEncoder().encode(Stored(fetchedAt: date, items: items)) else { return }
        defaults.set(data, forKey: key)
    }

    /// Sign-out: the next account must not see this one's replies.
    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
