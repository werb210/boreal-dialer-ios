// BOREAL_DIALER_v820_WATCH - the Watch asking the nearby iPhone to place a call, and the Watch handing a notification
// reply to the iPhone. Compiled into both targets (see WatchMessage.swift) so the keys and fields cannot drift.
import Foundation

/// BOREAL_DIALER_v820_WATCH - how a call started on the Watch is carried.
public enum WatchCallPath: String, Codable, Equatable, Sendable {
    /// The iPhone app places an ordinary Twilio/CallKit VoIP call. Audio follows iOS routing (AirPods, iPhone, Watch);
    /// no cellular minutes are used.
    case viaIPhone
    /// BF-Server's callback bridge (POST /telephony/watch/calls): Boreal rings the staff cell, which rings the Watch.
    case serverCallback

    /// A reachable iPhone app is always preferred; the server bridge is the fallback.
    public static func choose(companionReachable: Bool) -> WatchCallPath {
        companionReachable ? .viaIPhone : .serverCallback
    }

    /// The one line shown on the Watch call screen so the user knows which device will ring.
    public var banner: String {
        switch self {
        case .viaIPhone: return "Calling via iPhone"
        case .serverCallback: return "Boreal will ring your Watch, press 1 to connect"
        }
    }

    /// The status line under the banner. Bridge states come from BF-Server (versioned, authoritative); the iPhone path
    /// only knows that the iPhone started the call - CallKit shows the rest on the Watch and the iPhone.
    public static func statusText(_ status: WatchCallStatus, path: WatchCallPath?) -> String {
        switch (status, path) {
        case (.idle, _): return ""
        case (.requesting, .viaIPhone?): return "Asking your iPhone…"
        case (.requesting, _): return "Requesting call…"
        case (.ringing, .viaIPhone?): return "Calling… audio is on your iPhone or AirPods"
        case (.waitingForCallback, _), (.ringing, _): return "Ringing your Watch… answer, then press 1"
        case (.bridging, _): return "Answered. Connecting…"
        case (.connected, _): return "Connected. Hang up in the Phone app."
        case (.ended, _): return "Call ended"
        case (.failed, _): return "Call failed"
        }
    }
}

/// BOREAL_DIALER_v820_WATCH - sent with WCSession.sendMessage(_:replyHandler:) under WatchPayload.phoneCallKey.
public struct WatchPhoneCallRequest: Codable, Equatable, Sendable {
    public let destination: String
    public let contactId: String?
    public init(destination: String, contactId: String? = nil) {
        self.destination = destination
        self.contactId = contactId
    }
}

/// BOREAL_DIALER_v820_WATCH - the iPhone's answer. `reason` is a stable code when `accepted` is false.
public struct WatchPhoneCallReply: Codable, Equatable, Sendable {
    public let accepted: Bool
    public let reason: String?
    public init(accepted: Bool, reason: String? = nil) {
        self.accepted = accepted
        self.reason = reason
    }

    public static let reasonSignedOut = "signed_out"
    public static let reasonBusy = "busy"
    public static let reasonInvalidNumber = "invalid_number"
    public static let reasonMicrophone = "microphone"

    /// What the Watch shows when the iPhone refused. These are not transport failures, so they are not retried on the
    /// server bridge: a busy iPhone or a signed-out app would refuse there too, or ring a second call.
    public static func message(for reason: String?) -> String {
        switch reason {
        case reasonSignedOut: return "Sign in to Boreal Dialer on your iPhone."
        case reasonBusy: return "Your iPhone is already on a call."
        case reasonInvalidNumber: return "Enter a valid phone number"
        case reasonMicrophone: return "Open Boreal Dialer on your iPhone and allow the microphone."
        default: return "Your iPhone could not place the call."
        }
    }
}

/// BOREAL_DIALER_v820_WATCH - a Reply typed on the Watch for a mirrored iPhone notification that the Watch cannot send
/// itself (portal messages need the staff session, which only the iPhone holds).
public struct WatchAlertReplyMessage: Codable, Equatable, Sendable {
    public let kind: String
    public let contactId: String?
    public let phone: String?
    public let threadKind: String?
    public let body: String
    public init(kind: String, contactId: String?, phone: String?, threadKind: String? = nil, body: String) {
        self.kind = kind
        self.contactId = contactId
        self.phone = phone
        self.threadKind = threadKind
        self.body = body
    }

    /// The same fields as the push, so the iPhone resolves the target with the same rules (BorealAlertReplyTarget).
    public var userInfo: [AnyHashable: Any] {
        var info: [AnyHashable: Any] = ["type": kind]
        if let contactId { info["contactId"] = contactId }
        if let phone { info["phone"] = phone }
        if let threadKind { info["threadKind"] = threadKind }
        return info
    }
}

extension WatchPayload {
    public static let phoneCallKey = "boreal.watch.phonecall" // BOREAL_DIALER_v820_WATCH
    public static let phoneCallReplyKey = "boreal.watch.phonecall.reply" // BOREAL_DIALER_v820_WATCH
    public static let alertReplyKey = "boreal.watch.alertreply" // BOREAL_DIALER_v820_WATCH
}
