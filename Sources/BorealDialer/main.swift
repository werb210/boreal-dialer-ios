import SwiftUI
import UIKit

@main
struct BorealDialerApp: App {
    @StateObject var auth = AuthService.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        VoIPPushManager.shared.configure()
        _ = NetworkMonitor.shared
        _ = ReachabilityManager.shared
        _ = PersistenceController.shared
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
        }
    }
}
