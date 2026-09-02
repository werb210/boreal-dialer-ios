import SwiftUI
import UserNotifications
import WatchKit
import Security

final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        WatchNotificationRegistration.registerCategories(on: center)
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { WKApplication.shared().registerForRemoteNotifications() }
        }
    }
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        WatchPushTokenStore.shared.capture(deviceToken)
    }
    func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {}
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            WatchEventStore.shared.routeNotification(response.notification.request.content.userInfo)
            completionHandler()
        }
    }
}

enum WatchNotificationRegistration {
    static func registerCategories(on center: UNUserNotificationCenter) {
        let open = UNNotificationAction(identifier: "OPEN", title: "Open", options: [.foreground])
        let callback = UNNotificationAction(identifier: "CALL_BACK", title: "Call Back", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "MESSAGE", actions: [open], intentIdentifiers: []),
            UNNotificationCategory(identifier: "TASK", actions: [open], intentIdentifiers: []),
            UNNotificationCategory(identifier: "MEETING", actions: [open], intentIdentifiers: []),
            UNNotificationCategory(identifier: "MISSED_CALL", actions: [callback], intentIdentifiers: [])
        ])
    }
}

final class WatchPushTokenStore {
    static let shared = WatchPushTokenStore()
    private(set) var registration: DeviceRegistration?
    private let service = "financial.boreal.dialer.watch.apns"
    private let account = "watch-standard-token"
    func capture(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        let deviceId = WKInterfaceDevice.current().identifierForVendor?.uuidString ?? UUID().uuidString
        registration = DeviceRegistration(deviceId: deviceId, platform: .watchos, pushType: .standard, token: token)
        let delete: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(delete as CFDictionary)
        var add = delete
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
        // Upload waits for the documented authenticated registration API. The
        // Watch token has its own Keychain namespace and never transits iPhone.
    }
}

@main
struct BorealWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @StateObject private var store = WatchEventStore.shared
    var body: some Scene {
        WindowGroup { WatchRootView().environmentObject(store) }
    }
}
