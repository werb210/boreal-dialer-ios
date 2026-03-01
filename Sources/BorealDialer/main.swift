import AVFoundation
import SwiftUI
import UIKit
#if canImport(Sentry)
import Sentry
#endif

@main
struct BorealDialerApp: App {
    @StateObject var auth = AuthService.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        PushManager.shared.register()
        _ = VoiceEngine.shared
        _ = NetworkMonitor.shared
        _ = ReachabilityManager.shared
        _ = PersistenceController.shared

        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])

        ReconnectionController.shared.start()
#if canImport(Sentry)
        SentrySDK.start { options in
            options.dsn = "<dsn>"
            options.tracesSampleRate = 1.0
        }
#endif
        Telemetry.event("app_boot")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isAuthenticated {
                    RootTabView()
                } else {
                    LoginView()
                }
            }
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.willEnterForegroundNotification
            )) { _ in
                CallDurationManager.shared.resumeIfNeeded()
                Task {
                    await AuthService.shared.refreshTokenIfNeededOnResume()
                }
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
                if phase == .active {
                    Task {
                        await OfflineQueue.shared.flush()
                        try? await API.reconcileActiveCalls()
                    }
                }
            }

            .onReceive(NotificationCenter.default.publisher(
                for: UIScene.didDisconnectNotification
            )) { _ in
                TwilioVoiceManager.shared.disconnect()
                VoiceEngine.shared.forceTerminate()
            }
        }
    }
}
