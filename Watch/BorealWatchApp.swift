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
    private(set) var token: String?
    private let service = "financial.boreal.dialer.watch.apns"
    private let account = "watch-standard-token"
    private init() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
           let data = value as? Data {
            token = data.map { String(format: "%02x", $0) }.joined()
        }
    }
    func capture(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        self.token = token
        let delete: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(delete as CFDictionary)
        var add = delete
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
        Task { try? await uploadIfPossible() }
    }
    func uploadIfPossible(client supplied: WatchAPIClient? = nil) async throws {
        let client = try supplied ?? WatchAPIClient()
        guard let token, let current = await client.auth.session else { return }
        struct Body: Encodable { let pushType, token, environment: String }
#if DEBUG
        let environment = "sandbox"
#else
        let environment = "production"
#endif
        _ = try await client.request(path: "/watch/devices/\(current.deviceId)/push-token", method: "PUT",
            body: JSONEncoder().encode(Body(pushType: "standard", token: token, environment: environment)))
    }
    func clear() {
        token = nil
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
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
