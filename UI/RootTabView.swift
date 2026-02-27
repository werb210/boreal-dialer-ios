import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var voip = VoIPPushManager.shared

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
            VoiceService.shared.configureContext(modelContext)
            ConversationsService.shared.configureContext(modelContext)
        }
        .overlay {
            if voip.showIncomingUI,
               let caller = voip.incomingCaller {

                IncomingCallView(
                    caller: caller,
                    onAccept: {
                        voip.showIncomingUI = false
                        VoiceService.shared.answerIncomingCall()
                    },
                    onDecline: {
                        voip.showIncomingUI = false
                        VoiceService.shared.rejectIncomingCall()
                    }
                )
                .background(Color.black.opacity(0.9))
                .ignoresSafeArea()
            }
        }
    }
}
