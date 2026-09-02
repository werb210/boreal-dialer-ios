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
    case task
    case meeting
    case voicemail
    case stageChange
    case staffMessage
    case callInformation
}

public struct WatchEvent: Codable, Sendable, Equatable {
    public let kind: WatchEventKind
    public let callId: String
    /// May already be resolved by the sending service. The independent Watch
    /// can also refresh safe display data directly from Boreal.
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
        case .task: return "Task"
        case .meeting: return "Meeting"
        case .voicemail: return "Voicemail"
        case .stageChange: return "Application update"
        case .staffMessage: return "Staff message"
        case .callInformation: return "Call update"
        }
    }

    /// Falls back to the raw handle so an unknown number still reads as
    /// something dialable rather than an empty row.
    public var subtitle: String {
        displayName.isEmpty ? handle : displayName
    }
}

public enum BorealLine: String, Codable, CaseIterable, Sendable { case BF, BI, SLF }
public enum WatchCallDirection: String, Codable, Sendable { case incoming, outgoing, missed }
public enum WatchCallStatus: String, Codable, Sendable {
    case idle, requesting, waitingForCallback, ringing, connected, ended, failed
}
public struct CallRequest: Codable, Equatable, Sendable {
    public let destination: String
    public let line: BorealLine
    public let contactId: String?
    public init(destination: String, line: BorealLine, contactId: String? = nil) {
        self.destination = destination; self.line = line; self.contactId = contactId
    }
}
public struct ContactSummary: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let company: String?
    public let primaryPhone: String
    public init(id: String, name: String, company: String? = nil, primaryPhone: String) {
        self.id = id; self.name = name; self.company = company; self.primaryPhone = primaryPhone
    }
}
public struct WatchRecentCall: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String?
    public let number: String
    public let direction: WatchCallDirection
    public let occurredAt: Date
    public let line: BorealLine
}

public enum DevicePlatform: String, Codable, Sendable { case ios, watchos, android }
public enum PushType: String, Codable, Sendable { case standard, voip }
public struct DeviceRegistration: Codable, Equatable, Sendable {
    public let deviceId: String
    public let platform: DevicePlatform
    public let app: String
    public let pushType: PushType
    public let token: String
    public init(deviceId: String, platform: DevicePlatform, app: String = "boreal-dialer",
                pushType: PushType, token: String) {
        self.deviceId = deviceId; self.platform = platform; self.app = app
        self.pushType = pushType; self.token = token
    }
}

public enum PhoneNumberNormalizer {
    public static func normalize(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPlus = trimmed.hasPrefix("+")
        let digits = trimmed.filter(\.isNumber)
        guard (10...15).contains(digits.count) else { return nil }
        if hasPlus { return "+\(digits)" }
        if digits.count == 10 { return "+1\(digits)" }
        if digits.count == 11, digits.hasPrefix("1") { return "+\(digits)" }
        return nil
    }
}

public enum WatchDestination {
    case home, message(String?), task(String?), meeting(String?), missedCall(String?), call(String?), contact(String?)
}

/// Strict typed routing: notification data never becomes an executable URL.
public enum WatchNotificationRouter {
    public static func route(userInfo: [AnyHashable: Any]) -> WatchDestination {
        let id = safeIdentifier(userInfo["id"] as? String)
        switch userInfo["type"] as? String {
        case "client_message", "staff_message": return .message(id)
        case "task": return .task(id)
        case "meeting": return .meeting(id)
        case "missed_call": return .missedCall(id)
        case "call": return .call(id)
        case "contact": return .contact(id)
        default: return .home
        }
    }

    private static func safeIdentifier(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.count <= 128,
              value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_" )).contains($0) })
        else { return nil }
        return value
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
