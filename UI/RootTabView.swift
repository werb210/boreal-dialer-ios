import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext

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
        .onAppear {
            ConversationsService.shared.configureContext(modelContext)
        }
    }
}
