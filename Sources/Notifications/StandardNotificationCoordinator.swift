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
        _ = AppNotificationRouter.route(userInfo: response.notification.request.content.userInfo)
        // No matching native application/stage screen exists; retain a safe no-op.
        completion()
    }
}
