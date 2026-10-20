import Foundation
import UIKit
import UserNotifications

enum StandardPushToken: Equatable { case apns(Data) }

enum AppNotificationRoute: Equatable {
    case clientMessage(applicationId: String?)
    case stageChange(applicationId: String?)
    case unsupported
}

struct AppNotificationRouter {
    static func route(userInfo: [AnyHashable: Any]) -> AppNotificationRoute {
        let id = (userInfo["applicationId"] as? String).flatMap { $0.count <= 128 ? $0 : nil }
        switch userInfo["type"] as? String {
        case "client_message": return .clientMessage(applicationId: id)
        case "stage_change": return .stageChange(applicationId: id)
        default: return .unsupported
        }
    }
}

/// Ordinary APNs boundary.
/// BOREAL_DIALER_v820_WATCH - BF-Server v820 added POST/DELETE /staff/push-token, so the token is now uploaded
/// (StaffPushTokenRegistrar) and the five alert types (missed call, voicemail, SMS, client message, handoff) have
/// categories, actions and tap routing.
@MainActor
final class StandardNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = StandardNotificationCoordinator()
    private(set) var standardPushToken: StandardPushToken?

    private override init() { super.init() }

    func register() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // BOREAL_DIALER_MISSED_CALL_ACTIONS_v239 - the iPhone app registered no
        // categories, so a missed call could never show a Call Back button.
        // BOREAL_DIALER_v820_WATCH - all five alert categories (MISSED_CALL among them), shared with the Watch app so
        // mirrored notifications show the same Call back / Reply actions on the wrist.
        center.setNotificationCategories(Set(BorealAlertCategories.all()))
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func didReceiveStandardPushToken(_ token: Data) {
        standardPushToken = .apns(token)
        StaffPushTokenRegistrar.shared.didReceive(token) // BOREAL_DIALER_v820_WATCH
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        // BOREAL_DIALER_v821 - with the "Only client calls and messages" Focus filter on, internal alerts are not shown
        // while the app is open either (the system applies the same rule when it is not).
        completion(FocusAlertPolicy.presentationOptions(userInfo: notification.request.content.userInfo,
                                                        mode: FocusAlertPolicy.currentMode))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completion: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier
        // BOREAL_DIALER_v820_WATCH - a Reply typed on the banner, lock screen or the Watch. Sent in the background;
        // the completion handler is held until the send finishes so iOS keeps the app alive for it.
        if actionId == BorealAlertAction.reply, let text = (response as? UNTextInputNotificationResponse)?.userText {
            guard let payload = BorealAlertPayload(userInfo: userInfo),
                  let target = BorealAlertReplyTarget.target(for: payload) else {
                AlertReplySender.postFailure()
                completion()
                return
            }
            Task {
                do { try await AlertReplySender.send(text, to: target) }
                catch { AlertReplySender.postFailure() }
                completion()
            }
            return
        }
        // BOREAL_DIALER_MISSED_CALL_ACTIONS_v239 - Call Back dials through the existing deep-link path.
        // BOREAL_DIALER_v820_WATCH - only the Call back BUTTON dials now (missed call and voicemail). A plain tap on the
        // banner opens the Calls tab instead of ringing a client.
        if actionId == BorealAlertAction.callBack, let url = MissedCallNotification.callBackURL(userInfo: userInfo) {
            Task { @MainActor in _ = DeepLinkCoordinator.shared.receive(url) }
            completion()
            return
        }
        // BOREAL_DIALER_v820_WATCH - a tap opens the tab / thread the alert is about.
        if actionId == UNNotificationDefaultActionIdentifier,
           let destination = AlertDestination.destination(userInfo: userInfo) {
            Task { @MainActor in AlertNavigator.shared.open(destination) }
            completion()
            return
        }
        _ = AppNotificationRouter.route(userInfo: userInfo)
        // No matching native application/stage screen exists; retain a safe no-op.
        completion()
    }
}

// BOREAL_DIALER_MISSED_CALL_ACTIONS_v239
// Posted locally when a caller rings off before the call is answered, so it
// needs no server push and works as soon as the app handles the invite.
enum MissedCallNotification {
    static let categoryId = "MISSED_CALL"
    static let callBackActionId = "CALL_BACK"

    // BOREAL_DIALER_v820_WATCH - the shared definition, so the iPhone and the Watch register the same category.
    static func category() -> UNNotificationCategory {
        BorealAlertCategories.category(for: .missedCall)
    }

    /// Returns nil for anything that is not a dialable number (client identities, "Unknown").
    /// BOREAL_DIALER_v831_DIALER_POLISH - `whileOnCall`: a call that came in while you were on another one. It used to be
    /// turned away with no trace on the phone.
    static func content(handle: String, name: String? = nil, whileOnCall: Bool = false) -> UNMutableNotificationContent? {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.lowercased().hasPrefix("client:") else { return nil }
        let phone = String(trimmed.filter { $0.isNumber || $0 == "+" })
        guard phone.filter({ $0.isNumber }).count >= 7 else { return nil }
        let content = UNMutableNotificationContent()
        content.title = whileOnCall ? "Missed while you were on a call" : "Missed call"
        let display = PhoneFormat.display(trimmed)
        let shown = display.isEmpty ? trimmed : display
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            content.body = "\(name) · \(shown)"
        } else {
            content.body = trimmed
        }
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = ["type": "missed_call", "phone": phone, MissedCallDedupe.localKey: true] // BOREAL_DIALER_v832_SIGNOUT_ALERTS
        FocusAlertPolicy.tag(content, as: .client) // BOREAL_DIALER_v821 - time-sensitive client alert
        return content
    }

    static func callBackURL(userInfo: [AnyHashable: Any]) -> URL? {
        // BOREAL_DIALER_v820_WATCH - voicemail pushes offer Call back too, and the phone is normalised to E.164 (the
        // deep-link parser rejects anything else).
        guard let payload = BorealAlertPayload(userInfo: userInfo), payload.kind.offersCallBack,
              let phone = payload.phone else { return nil }
        var components = URLComponents()
        components.scheme = "borealdialer"
        components.host = "call"
        components.queryItems = [
            URLQueryItem(name: "phone", value: phone),
            URLQueryItem(name: "start", value: "true")
        ]
        return components.url
    }

    static func post(handle: String, name: String? = nil, whileOnCall: Bool = false, center: UNUserNotificationCenter = .current()) {
        guard let content = content(handle: handle, name: name, whileOnCall: whileOnCall) else { return }
        let request = UNNotificationRequest(identifier: "missed-call-\(UUID().uuidString)", content: content, trigger: nil)
        // BOREAL_DIALER_v832_SIGNOUT_ALERTS - not when the server's alert for this caller is already showing.
        let phone = content.userInfo["phone"] as? String
        center.getDeliveredNotifications { delivered in
            let entries = delivered.map {
                MissedCallDedupe.Delivered(id: $0.request.identifier, userInfo: $0.request.content.userInfo, date: $0.date)
            }
            guard !MissedCallDedupe.serverAlerted(for: phone, in: entries) else { return }
            center.add(request, withCompletionHandler: nil)
        }
    }
}
