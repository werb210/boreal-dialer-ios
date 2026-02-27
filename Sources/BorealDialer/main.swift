import SwiftUI
import SwiftData
import UIKit

@main
struct BorealDialerApp: App {
    @StateObject var auth = AuthService.shared

    init() {
        _ = VoIPPushManager.shared
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
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.willEnterForegroundNotification
            )) { _ in
                CallDurationManager.shared.resumeIfNeeded()
            }
        }
        .modelContainer(for: [
            CallLog.self,
            StoredMessage.self
        ])
    }
}
