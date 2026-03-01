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

            NavigationView {
                CallHistoryView()
            }
            .tabItem {
                Label("Calls", systemImage: "phone.fill")
            }

            NavigationView {
                LineSwitcherView()
            }
            .tabItem {
                Label("Lines", systemImage: "square.stack")
            }
        }
    }
}
