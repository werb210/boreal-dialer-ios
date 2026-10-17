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
    // BOREAL_DIALER_v819_PUSH - with no willPresent handler a push that arrived while the Watch app was open was
    // silently dropped by the system. Show it as a banner like any other notification.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
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
    // BOREAL_DIALER_v819_PUSH - the token was uploaded only at launch and right after linking, both with try?. One
    // failed upload (offline, expired session) left the server with no registration until the Watch app was next
    // cold-launched, which on watchOS can be days. Re-send it when the app becomes active, at most every 6 hours.
    private var lastUploadedToken: String?
    private var lastUploadedAt: Date?
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
        await MainActor.run { WatchPushTokenStore.shared.markUploaded(token) } // BOREAL_DIALER_v819_PUSH - throttle state
    }
    // BOREAL_DIALER_v819_PUSH - see lastUploadedToken.
    @MainActor func markUploaded(_ value: String) {
        lastUploadedToken = value
        lastUploadedAt = Date()
    }
    // BOREAL_DIALER_v819_PUSH - called whenever the Watch app becomes active.
    @MainActor func refreshRegistrationIfNeeded() {
        guard let token else { return }
        if token == lastUploadedToken, let at = lastUploadedAt, Date().timeIntervalSince(at) < 6 * 60 * 60 { return }
        Task { try? await WatchPushTokenStore.shared.uploadIfPossible() }
    }
    func clear() {
        token = nil
        lastUploadedToken = nil // BOREAL_DIALER_v819_PUSH
        lastUploadedAt = nil
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    }
}

@main
struct BorealWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @StateObject private var store = WatchEventStore.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
                // BOREAL_DIALER_WATCH_FACE_v371
                .onOpenURL { url in store.complicationTarget = WatchComplicationLink.target(for: url) }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    WatchPushTokenStore.shared.refreshRegistrationIfNeeded() // BOREAL_DIALER_v819_PUSH
                    Task { await WatchFaceSync.refresh() }
                    WatchFaceSync.scheduleNext()
                }
        }
        .backgroundTask(.appRefresh(WatchFaceSync.refreshTaskID)) {
            await WatchFaceSync.refresh()
            await MainActor.run { WatchFaceSync.scheduleNext() }
        }
    }
}
