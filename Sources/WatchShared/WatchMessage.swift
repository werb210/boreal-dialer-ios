// BOREAL_DIALER_WATCH_v55
// The one vocabulary both the phone and the watch speak. Compiled into both
// targets so a field renamed on one side cannot silently diverge from the other:
// WCSession carries [String: Any] dictionaries with no schema of their own, and
// a typo in a raw string key fails at runtime on a wrist, where nobody is
// looking at a console.
import Foundation

public enum WatchEventKind: String, Codable, Sendable {
    case incomingCall
    case missedCall
    case newMessage
}

public struct WatchEvent: Codable, Sendable, Equatable {
    public let kind: WatchEventKind
    public let callId: String
    /// Already resolved to a CRM name where one exists, because the watch has
    /// no contact store of its own and must not do a lookup on the wrist.
    public let displayName: String
    public let handle: String
    public let preview: String
    public let occurredAt: Date

    public init(kind: WatchEventKind, callId: String, displayName: String,
                handle: String, preview: String = "", occurredAt: Date = Date()) {
        self.kind = kind
        self.callId = callId
        self.displayName = displayName
        self.handle = handle
        self.preview = preview
        self.occurredAt = occurredAt
    }

    public var title: String {
        switch kind {
        case .incomingCall: return "Incoming call"
        case .missedCall: return "Missed call"
        case .newMessage: return "New message"
        }
    }

    /// Falls back to the raw handle so an unknown number still reads as
    /// something dialable rather than an empty row.
    public var subtitle: String {
        displayName.isEmpty ? handle : displayName
    }
}

public enum WatchAction: String, Codable, Sendable {
    case answer
    case decline
}

public struct WatchActionMessage: Codable, Sendable, Equatable {
    public let action: WatchAction
    public let callId: String

    public init(action: WatchAction, callId: String) {
        self.action = action
        self.callId = callId
    }
}

public enum WatchPayload {
    public static let eventKey = "boreal.watch.event"
    public static let actionKey = "boreal.watch.action"

    public static func encode<T: Encodable>(_ value: T, under key: String) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(value) else { return [:] }
        return [key: data]
    }

    public static func decode<T: Decodable>(_ type: T.Type, from message: [String: Any], key: String) -> T? {
        guard let data = message[key] as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
