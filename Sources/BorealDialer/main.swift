import SwiftUI
import UIKit

@main
struct BorealDialerApp: App {
    @StateObject var auth = AuthService.shared

    init() {
        VoIPPushManager.shared.configure()
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
        }
    }
}
