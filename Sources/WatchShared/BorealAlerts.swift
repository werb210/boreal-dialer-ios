// BOREAL_DIALER_v820_WATCH - one definition of the BF-Server v820 alert pushes, compiled into the iPhone app AND the
// Watch app. iPhone notifications mirror to the Watch when the iPhone is locked, and the Watch uses ITS OWN registered
// category for a mirrored notification when it declares one, so the two sides must register identical categories or the
// Call back / Reply buttons silently vanish on the wrist.
import Foundation
import UserNotifications

/// BOREAL_DIALER_v820_WATCH - the five alert types (top-level "type"; aps.category is the uppercased form).
public enum BorealAlertKind: String, CaseIterable, Sendable {
    case missedCall = "missed_call"
    case voicemail
    case clientMessage = "client_message"
    case sms
    case handoff

    public var categoryId: String { rawValue.uppercased() }

    public init?(categoryId: String) {
        guard let kind = BorealAlertKind.allCases.first(where: { $0.categoryId == categoryId }) else { return nil }
        self = kind
    }

    /// Missed calls and voicemails offer Call back; texts and portal messages offer Reply.
    public var offersCallBack: Bool { self == .missedCall || self == .voicemail }
}

/// BOREAL_DIALER_v820_WATCH - action identifiers. CALL_BACK is the identifier v239 already shipped for missed calls.
public enum BorealAlertAction {
    public static let callBack = "CALL_BACK"
    public static let reply = "REPLY"
}

/// BOREAL_DIALER_v820_WATCH - the validated fields of an alert push. Nothing in here ever becomes a URL or a request
/// path without passing the same checks the deep-link parser uses.
public struct BorealAlertPayload: Equatable, Sendable {
    public let kind: BorealAlertKind
    public let contactId: String?
    /// E.164, or nil when absent or not a dialable number.
    public let phone: String?
    /// "sms" or "messages" when the server says which thread a handoff belongs to.
    public let threadKind: String?
    /// BOREAL_DIALER_v821 - VOICEMAIL alerts carry the voicemail's id (top-level "voicemailId"); a tap opens it.
    public let voicemailId: String?

    public init(kind: BorealAlertKind, contactId: String? = nil, phone: String? = nil, threadKind: String? = nil,
                voicemailId: String? = nil) {
        self.kind = kind
        self.contactId = contactId
        self.phone = phone
        self.threadKind = threadKind
        self.voicemailId = voicemailId
    }

    public init?(userInfo: [AnyHashable: Any]) {
        let typed = (userInfo["type"] as? String).flatMap { BorealAlertKind(rawValue: $0.lowercased()) }
        let aps = userInfo["aps"] as? [String: Any]
        let categorised = (aps?["category"] as? String).flatMap { BorealAlertKind(categoryId: $0) }
        guard let kind = typed ?? categorised else { return nil }
        self.kind = kind
        self.contactId = Self.safeIdentifier(userInfo["contactId"] as? String)
        self.phone = (userInfo["phone"] as? String).flatMap { PhoneNumberNormalizer.normalize($0) }
        let thread = (userInfo["threadKind"] as? String)?.lowercased()
        self.threadKind = (thread == "sms" || thread == "messages") ? thread : nil
        // BOREAL_DIALER_v821 - only kept for voicemail alerts, and only when it is a plain identifier.
        self.voicemailId = kind == .voicemail ? Self.safeIdentifier(userInfo["voicemailId"] as? String) : nil
    }

    /// A handoff lands in the SMS thread when the server says so (or only a phone is known); otherwise in Messages.
    public var opensSMSThread: Bool {
        switch kind {
        case .sms: return true
        case .handoff: return threadKind == "sms" || (threadKind == nil && contactId == nil && phone != nil)
        default: return false
        }
    }

    static func safeIdentifier(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.count <= 128,
              value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { return nil }
        return value
    }
}

/// BOREAL_DIALER_v820_WATCH - where a typed Reply goes.
public enum BorealAlertReplyTarget: Equatable, Sendable {
    /// POST /communications/sms {to, body, contactId}
    case sms(phone: String, contactId: String?)
    /// POST /communications/messages/send {contactId, body}
    case portalMessage(contactId: String)

    public static func target(for payload: BorealAlertPayload) -> BorealAlertReplyTarget? {
        switch payload.kind {
        case .missedCall, .voicemail:
            return nil
        case .sms, .clientMessage, .handoff:
            if payload.opensSMSThread {
                guard let phone = payload.phone else { return nil }
                return .sms(phone: phone, contactId: payload.contactId)
            }
            if let contactId = payload.contactId { return .portalMessage(contactId: contactId) }
            // A client message with no contact cannot be answered in the portal thread; a known number can still be texted.
            if payload.kind == .sms, let phone = payload.phone { return .sms(phone: phone, contactId: nil) }
            return nil
        }
    }
}

/// BOREAL_DIALER_v820_WATCH - the categories both apps register.
public enum BorealAlertCategories {
    public static func callBackAction() -> UNNotificationAction {
        // Foreground: placing a call needs the app (CallKit on the iPhone, the call screen on the Watch).
        UNNotificationAction(identifier: BorealAlertAction.callBack, title: "Call back",
                             options: [.foreground, .authenticationRequired])
    }

    public static func replyAction() -> UNTextInputNotificationAction {
        // Not foreground: the reply is sent in the background, so it works from the lock screen and the Watch.
        UNTextInputNotificationAction(identifier: BorealAlertAction.reply, title: "Reply",
                                      options: [.authenticationRequired],
                                      textInputButtonTitle: "Send",
                                      textInputPlaceholder: "Message")
    }

    public static func category(for kind: BorealAlertKind) -> UNNotificationCategory {
        let actions: [UNNotificationAction] = kind.offersCallBack ? [callBackAction()] : [replyAction()]
        return UNNotificationCategory(identifier: kind.categoryId, actions: actions, intentIdentifiers: [], options: [])
    }

    public static func all() -> [UNNotificationCategory] {
        BorealAlertKind.allCases.map { category(for: $0) }
    }
}
