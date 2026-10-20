// BOREAL_DIALER_v820_WATCH - iPhone side of the BF-Server v820 alert pushes: the APNs token upload
// (POST/DELETE /staff/push-token), where a tapped alert lands, and how a typed Reply is sent.
import Foundation
import UserNotifications

// MARK: - Where a tapped alert opens

/// BOREAL_DIALER_v820_WATCH
enum AlertDestination: Equatable {
    /// Calls tab, Recents.
    case calls
    /// Calls tab, Voicemail.
    case voicemail
    /// BOREAL_DIALER_v821 - Calls tab, Voicemail, with this voicemail opened (transcript, play, call back).
    case voicemailMessage(id: String)
    /// SMS tab, the thread for this number / contact.
    case smsThread(phone: String?, contactId: String?)
    /// Messages tab, the portal conversation for this contact.
    case messagesConversation(contactId: String)
    /// Messages tab, list (a client message with no usable contact id).
    case messages

    static func destination(for payload: BorealAlertPayload) -> AlertDestination {
        switch payload.kind {
        case .missedCall: return .calls
        case .voicemail:
            // BOREAL_DIALER_v821 - straight to the voicemail the alert is about.
            if let id = payload.voicemailId { return .voicemailMessage(id: id) }
            return .voicemail
        case .sms, .clientMessage, .handoff:
            if payload.opensSMSThread {
                if payload.phone == nil && payload.contactId == nil { return .messages }
                return .smsThread(phone: payload.phone, contactId: payload.contactId)
            }
            if let contactId = payload.contactId { return .messagesConversation(contactId: contactId) }
            return .messages
        }
    }

    static func destination(userInfo: [AnyHashable: Any]) -> AlertDestination? {
        BorealAlertPayload(userInfo: userInfo).map { destination(for: $0) }
    }

    var tab: RootTabView.Tab {
        switch self {
        case .calls, .voicemail, .voicemailMessage: return .calls
        case .smsThread: return .sms
        case .messagesConversation, .messages: return .messages
        }
    }
}

/// BOREAL_DIALER_v820_WATCH - holds a tapped alert until the tab that shows it is on screen. RootTabView switches tab;
/// CallsView / SMSView / MessagesView consume the part that is theirs. A value set before sign-in or before RootTabView
/// exists waits, because @Published replays its current value to each new subscriber.
@MainActor
final class AlertNavigator: ObservableObject {
    static let shared = AlertNavigator()
    @Published private(set) var pending: AlertDestination?
    private init() {}

    func open(_ destination: AlertDestination) { pending = destination }

    /// Marks `destination` handled. @Published emits from willSet, so a subscriber that cleared `pending` synchronously
    /// inside onReceive would be overwritten by the value still being set; the clear is deferred to a later main-actor turn.
    func finish(_ destination: AlertDestination) {
        Task { @MainActor in
            if AlertNavigator.shared.pending == destination { AlertNavigator.shared.pending = nil }
        }
    }
}

// MARK: - APNs token upload

/// BOREAL_DIALER_v820_WATCH - same rule the Watch uses for its own token (Watch/BorealWatchApp.swift): DEBUG builds are
/// signed for the APNs sandbox, Release/TestFlight/App Store builds for production.
enum PushTokenEnvironment {
    static func value(isDebug: Bool) -> String { isDebug ? "sandbox" : "production" }

    static var current: String {
#if DEBUG
        return value(isDebug: true)
#else
        return value(isDebug: false)
#endif
    }

    static func hex(_ token: Data) -> String { token.map { String(format: "%02x", $0) }.joined() }
}

/// BOREAL_DIALER_v820_WATCH - the iPhone received an APNs token and never sent it anywhere, so no alert push could reach
/// it. Uploaded after sign-in, whenever the token changes, and again at most every 6 hours on foreground; removed on sign-out.
@MainActor
final class StaffPushTokenRegistrar {
    static let shared = StaffPushTokenRegistrar()
    static let appName = "dialer-ios"
    private(set) var token: String?
    private var lastUploadedToken: String?
    private var lastUploadedAt: Date?
    private var uploading = false
    private init() {}

    struct RegisterBody: Encodable, Equatable {
        let token: String
        let environment: String
        let app: String
    }

    static func registerBody(token: String, environment: String = PushTokenEnvironment.current) -> RegisterBody {
        RegisterBody(token: token, environment: environment, app: appName)
    }

    /// Upload when the token is new or the last upload is older than `maxAge`.
    static func needsUpload(token: String?, lastUploadedToken: String?, lastUploadedAt: Date?, now: Date,
                            maxAge: TimeInterval = 6 * 60 * 60) -> Bool {
        guard let token, !token.isEmpty else { return false }
        guard token == lastUploadedToken, let lastUploadedAt else { return true }
        return now.timeIntervalSince(lastUploadedAt) >= maxAge
    }

    func didReceive(_ data: Data) {
        token = PushTokenEnvironment.hex(data)
        uploadIfNeeded()
    }

    /// Called after sign-in and on foreground. A no-op when signed out or already current.
    func uploadIfNeeded(force: Bool = false) {
        guard !uploading, TokenStorage.shared.getToken() != nil else { return }
        guard force || Self.needsUpload(token: token, lastUploadedToken: lastUploadedToken,
                                        lastUploadedAt: lastUploadedAt, now: Date()) else { return }
        guard let token else { return }
        uploading = true
        Task {
            defer { StaffPushTokenRegistrar.shared.uploading = false }
            do {
                let body = try JSONEncoder().encode(Self.registerBody(token: token))
                let request = try APIClient.shared.makeRequest(path: "/staff/push-token", method: "POST", body: body)
                _ = try await APIClient.shared.makeAuthorizedRequest(request)
                StaffPushTokenRegistrar.shared.lastUploadedToken = token
                StaffPushTokenRegistrar.shared.lastUploadedAt = Date()
            } catch {
                // Retried on the next foreground or token change; the silent-failure rule is to log, not swallow.
                Telemetry.event("push_token_upload_failed")
            }
        }
    }

    /// Sign-out: the server must stop sending this account's alerts to this phone. Runs before the staff token is cleared.
    func unregister() async {
        defer { lastUploadedToken = nil; lastUploadedAt = nil }
        guard let token, TokenStorage.shared.getToken() != nil else { return }
        do {
            let body = try JSONEncoder().encode(["token": token])
            let request = try APIClient.shared.makeRequest(path: "/staff/push-token", method: "DELETE", body: body)
            _ = try await APIClient.shared.makeAuthorizedRequest(request)
        } catch {
            Telemetry.event("push_token_delete_failed")
            // BOREAL_DIALER_v832_SIGNOUT_ALERTS - sent again when the signal returns (PendingSignOut), unless the server
            // refused it outright.
            if case APIError.http(let status, _, _) = error, PendingSignOut.alertUnregisterIsDone(status: status) { return }
            if case APIError.unauthorized = error { return } // the server already refuses this sign-in
            if let staffToken = TokenStorage.shared.getToken() {
                PendingSignOut.rememberAlertUnregister(pushToken: token, staffToken: staffToken)
            }
        }
    }
}

// MARK: - Reply

/// BOREAL_DIALER_v820_WATCH - sends a Reply typed on a notification (iPhone lock screen, banner, or the Watch).
enum AlertReplySender {
    enum ReplyError: Error { case empty, noTarget }

    static func send(_ body: String, to target: BorealAlertReplyTarget) async throws {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ReplyError.empty }
        switch target {
        case .sms(let phone, let contactId):
            // The same send the SMS tab uses.
            try await API.sendSMS(SendSMSPayload(to: phone, body: text, contactId: contactId))
        case .portalMessage(let contactId):
            // The same send the Messages tab uses (MessagesView.swift).
            let payload = try JSONSerialization.data(withJSONObject: ["contactId": contactId, "body": text])
            let request = try APIClient.shared.makeRequest(path: "/communications/messages/send", method: "POST", body: payload)
            _ = try await APIClient.shared.makeAuthorizedRequest(request)
        }
    }

    /// A reply that could not be sent must not vanish: say so on the lock screen / Watch.
    static func postFailure(center: UNUserNotificationCenter = .current()) {
        let content = UNMutableNotificationContent()
        content.title = "Reply not sent"
        content.body = "Open Boreal Dialer to try again."
        content.sound = .default
        content.userInfo = ["type": "reply_failed"] // BOREAL_DIALER_v821 - a client reply: shown under the client-only Focus
        FocusAlertPolicy.tag(content, as: .client)
        center.add(UNNotificationRequest(identifier: "reply-failed-\(UUID().uuidString)", content: content, trigger: nil),
                   withCompletionHandler: nil)
    }
}
