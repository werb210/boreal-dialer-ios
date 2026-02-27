import SwiftUI
import SwiftData

@main
struct BorealDialerApp: App {
    @StateObject var auth = AuthService.shared

    init() {
        _ = VoIPPushManager.shared
    }

    var body: some Scene {
        WindowGroup {
            if auth.isAuthenticated {
                RootTabView()
            } else {
                LoginView()
            }
        }
        .modelContainer(for: [
            CallLog.self,
            StoredMessage.self
        ])
    }
}
