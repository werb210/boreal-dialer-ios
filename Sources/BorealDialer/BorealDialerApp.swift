import Foundation
import AVFoundation
import SwiftUI
import UIKit
import LocalAuthentication
#if canImport(Sentry)
import Sentry
#endif

@main
struct BorealDialerApp: App {
    @UIApplicationDelegateAdaptor(DialerAppDelegate.self) private var appDelegate
    @StateObject var auth = AuthService.shared
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appLock = AppLockController.shared // BOREAL_DIALER_FACE_ID_v244

    init() {
        PushManager.shared.register()
        StandardNotificationCoordinator.shared.register()
        WatchBridge.shared.activate() // BOREAL_DIALER_WATCH_v55
        _ = VoiceEngine.shared
        _ = NetworkMonitor.shared
        _ = ReachabilityManager.shared
        _ = PersistenceController.shared

        ReconnectionController.shared.start()
#if canImport(Sentry)
        // BOREAL_DIALER_XCODEGEN_v1 - was a literal "<dsn>" placeholder, which
        // would have shipped a broken Sentry init. Driven by Info.plist so a
        // build without the key simply skips Sentry.
        if let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
           !dsn.isEmpty {
            SentrySDK.start { options in
                options.dsn = dsn
                options.tracesSampleRate = 1.0
            }
        }
#endif
        Telemetry.event("app_boot")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isAuthenticated {
                    RootTabView()
                // BOREAL_DIALER_THEME_v27 - the concept is a dark theme; the
                // app was rendering in default light SwiftUI.
                .preferredColorScheme(.dark)
                .tint(Theme.green)
                .background(Theme.bg.ignoresSafeArea())
                .overlay { if appLock.isLocked { AppLockView(lock: appLock) } } // BOREAL_DIALER_FACE_ID_v244
                } else {
                    LoginView()
                }
            }
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            .onOpenURL { _ = DeepLinkCoordinator.shared.receive($0) }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.willEnterForegroundNotification
            )) { _ in
                CallDurationManager.shared.resumeIfNeeded()
            }
            .onReceive(NetworkMonitor.shared.$isConnected) { connected in
                if connected {
                    Task {
                        await OfflineQueue.shared.flush()
                    }
                    VoiceManager.shared.handleNetworkReconnect()
                    Telemetry.event("network_recovered")
                }
            }
            .onChange(of: scenePhase) { phase in
                // BOREAL_DIALER_FACE_ID_v244 - re-lock a signed-in session on return.
                if phase == .active { appLock.didBecomeActive(authenticated: auth.isAuthenticated) }
                if phase == .background { appLock.didEnterBackground() }
                if phase == .active {
                    WidgetSnapshotStore.refreshStoredSnapshot()
                    // BOREAL_DIALER_WATCH_SNAPSHOT_WRITER_v210 - nothing has ever written the
                    // keys the watch complication reads. This is that writer.
                    Task { await WatchSnapshotSync.refresh() }
                    Task {
                        await OfflineQueue.shared.flush()
                        await CallDirectoryManager.shared.refresh()
                        CallDirectoryManager.shared.updateEnabledStatus()
                        // BOREAL_DIALER_PRESENCE_v41
                        PresenceHeartbeat.shared.start()
                        // BOREAL_DIALER_WATCH_ENROLL_v146 - hand the wrist a
                        // link code so it can authenticate itself. No-op once
                        // the Watch already holds a token.
                        await WatchEnrollment.shared.enrollWatchIfNeeded()
                    }
                }

                if phase == .background {
                    // BOREAL_DIALER_PRESENCE_v41 - a backgrounded phone is not available.
                    Task { await PresenceHeartbeat.shared.goOffline() }
                }

                // Scene disconnection (including iPad multitasking) is not a
                // call-lifecycle event. Twilio/CallKit remain authoritative.
            }
        }
    }
}

final class DialerAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        DeepLinkCoordinator.shared.receive(url)
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            StandardNotificationCoordinator.shared.didReceiveStandardPushToken(deviceToken)
        }
    }
}

// BOREAL_DIALER_FACE_ID_v244
// Face ID / Touch ID (passcode fallback) to re-enter an already signed-in
// session. Never locks during a call, so answering from CallKit is untouched.
enum AppLockPolicy {
    static let lockAfter: TimeInterval = 60

    static func shouldLock(authenticated: Bool, biometryAvailable: Bool, inCall: Bool,
                           coldStart: Bool, backgroundedAt: Date?, now: Date) -> Bool {
        guard authenticated, biometryAvailable, !inCall else { return false }
        if coldStart { return true }
        guard let backgroundedAt else { return false }
        return now.timeIntervalSince(backgroundedAt) >= lockAfter
    }
}

@MainActor
final class AppLockController: ObservableObject {
    static let shared = AppLockController()
    @Published private(set) var isLocked = false
    @Published private(set) var errorMessage: String?
    private var backgroundedAt: Date?
    private var hasBecomeActive = false
    private var authenticating = false

    func didEnterBackground() {
        if !isLocked { backgroundedAt = Date() }
    }

    func didBecomeActive(authenticated: Bool) {
        let coldStart = !hasBecomeActive
        hasBecomeActive = true
        let lock = AppLockPolicy.shouldLock(
            authenticated: authenticated,
            biometryAvailable: Self.biometryAvailable(),
            inCall: Self.inCall(),
            coldStart: coldStart,
            backgroundedAt: backgroundedAt,
            now: Date()
        )
        backgroundedAt = nil
        if lock {
            isLocked = true
            unlock()
        }
    }

    func unlock() {
        guard !authenticating else { return }
        authenticating = true
        errorMessage = nil
        LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Boreal Dialer") { success, _ in
            Task { @MainActor in
                AppLockController.shared.finishUnlock(success: success)
            }
        }
    }

    private func finishUnlock(success: Bool) {
        authenticating = false
        if success { isLocked = false } else { errorMessage = "Not recognised. Try again." }
    }

    func signOutInstead() {
        isLocked = false
        Task { await AuthService.shared.logout() }
    }

    private static func biometryAvailable() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    private static func inCall() -> Bool {
        switch VoiceEngine.shared.state {
        case .ringing, .dialing, .active: return true
        default: return false
        }
    }
}

struct AppLockView: View {
    @ObservedObject var lock: AppLockController

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.green)
                Text("Boreal Dialer is locked")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Button("Unlock") { lock.unlock() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.green)
                if let message = lock.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
                Button("Sign out") { lock.signOutInstead() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}
