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

/// Ordinary APNs boundary. No server upload is attempted because this repo has
/// no verified standard-token registration endpoint.
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
        center.setNotificationCategories([MissedCallNotification.category()])
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func didReceiveStandardPushToken(_ token: Data) {
        standardPushToken = .apns(token)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completion: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        // BOREAL_DIALER_MISSED_CALL_ACTIONS_v239 - Call Back (or a tap on the
        // missed-call banner) dials through the existing deep-link path.
        if let url = MissedCallNotification.callBackURL(userInfo: userInfo) {
            Task { @MainActor in _ = DeepLinkCoordinator.shared.receive(url) }
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

    static func category() -> UNNotificationCategory {
        let callBack = UNNotificationAction(
            identifier: callBackActionId,
            title: "Call Back",
            options: [.foreground, .authenticationRequired]
        )
        return UNNotificationCategory(identifier: categoryId, actions: [callBack], intentIdentifiers: [], options: [])
    }

    /// Returns nil for anything that is not a dialable number (client identities, "Unknown").
    static func content(handle: String) -> UNMutableNotificationContent? {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.lowercased().hasPrefix("client:") else { return nil }
        let phone = String(trimmed.filter { $0.isNumber || $0 == "+" })
        guard phone.filter({ $0.isNumber }).count >= 7 else { return nil }
        let content = UNMutableNotificationContent()
        content.title = "Missed call"
        content.body = trimmed
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = ["type": "missed_call", "phone": phone]
        return content
    }

    static func callBackURL(userInfo: [AnyHashable: Any]) -> URL? {
        guard userInfo["type"] as? String == "missed_call",
              let phone = userInfo["phone"] as? String,
              !phone.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "borealdialer"
        components.host = "call"
        components.queryItems = [
            URLQueryItem(name: "phone", value: phone),
            URLQueryItem(name: "start", value: "true")
        ]
        return components.url
    }

    static func post(handle: String, center: UNUserNotificationCenter = .current()) {
        guard let content = content(handle: handle) else { return }
        let request = UNNotificationRequest(identifier: "missed-call-\(UUID().uuidString)", content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }
}
