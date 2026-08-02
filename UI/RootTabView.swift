import SwiftUI

// boreal-dialer-ios v4 — top tab strip: Calls / Messages / SMS / Team / Notifications.
struct RootTabView: View {
    enum Tab: String, CaseIterable {
        // BOREAL_DIALER_CONTACTS_TAB_v7
        case calls = "Calls", contacts = "Contacts", messages = "Messages",
             sms = "SMS", team = "Team", notifications = "Notifications"
    }

    @State private var tab: Tab = .calls

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Button {
                            tab = t
                        } label: {
                            VStack(spacing: 4) {
                                Text(t.rawValue)
                                    .font(.footnote)
                                    .fontWeight(tab == t ? .semibold : .regular)
                                Rectangle()
                                    .fill(tab == t ? Color.accentColor : Color.clear)
                                    .frame(height: 2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                        }
                        .foregroundColor(tab == t ? .primary : .secondary)
                        .buttonStyle(.plain)
                        .frame(minWidth: 88)
                    }
                }
            }
            Divider()

            Group {
                switch tab {
                case .calls: DialerView()
                case .contacts: ContactsView()
                case .messages: MessagesView()
                case .sms: SMSView()
                case .team: TeamView()
                case .notifications: NotificationsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
