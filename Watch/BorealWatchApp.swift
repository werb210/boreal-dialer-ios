// BOREAL_DIALER_WATCH_v55
// Notification-only by design. Placing a call from the wrist needs audio routing
// the watch cannot give a Twilio session, so the watch reports and hands off.
import SwiftUI

@main
struct BorealWatchApp: App {
    @StateObject private var store = WatchEventStore.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
        }
    }
}
