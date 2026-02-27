import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            DialerView()
                .tabItem {
                    Label("Call", systemImage: "phone.fill")
                }

            MessagesView()
                .tabItem {
                    Label("Messages", systemImage: "message")
                }

            CallHistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
        }
    }
}
