import SwiftUI
import SwiftData

@main
struct BorealDialerApp: App {
    @StateObject private var authManager = AuthManager.shared

    init() {
        _ = VoIPPushManager.shared
    }

    var body: some Scene {
        WindowGroup {
            if authManager.isSignedIn {
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
