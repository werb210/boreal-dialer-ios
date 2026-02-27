import SwiftUI

@main
struct BorealDialerApp: App {
    @StateObject private var authManager = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            if authManager.isSignedIn {
                RootTabView()
            } else {
                LoginView()
            }
        }
    }
}
