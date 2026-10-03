import SwiftUI

// boreal-dialer-ios v4 — top tab strip: Calls / Messages / SMS / Team / Notifications.
struct RootTabView: View {
    // BOREAL_DIALER_ACCOUNT_SHEET_v42
    @State private var showAccount = false

    enum Tab: String, CaseIterable {
        // BOREAL_DIALER_CONTACTS_TAB_v7
        // BOREAL_DIALER_CALENDAR_TAB_v8 - the six tabs from the concept mockup.
        case calls = "Calls", contacts = "Contacts", messages = "Messages",
             sms = "SMS", team = "Team", calendar = "Calendar"
    }

    @State private var tab: Tab = .calls
    @ObservedObject private var deepLinks = DeepLinkCoordinator.shared

    var body: some View {
        VStack(spacing: 0) {
            OfflineStatusBar() // BOREAL_DIALER_OFFLINE_v303
            // BOREAL_DIALER_MOCKUP_LAYOUT_v60 - mockup tab strip: pills sized to their
            // text, 8 pt apart, semibold; the account button sits at the row's end.
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Tab.allCases, id: \.self) { t in
                            Button {
                                tab = t
                            } label: {
                                Text(t.rawValue)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 9)
                                    .background(Capsule().fill(tab == t ? Theme.green : Color.clear))
                                    .overlay(Capsule().stroke(tab == t ? Color.clear : Theme.line2, lineWidth: 1))
                                    .foregroundColor(tab == t ? Theme.onGreen : Theme.muted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.vertical, 10)
                }
                Button {
                    showAccount = true
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.muted)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 14)
                .accessibilityLabel("Account")
            }
            Divider().overlay(Theme.line)

            Group {
                switch tab {
                // BOREAL_DIALER_CALLS_TAB_v11 - Keypad / Recents / Voicemail.
                case .calls: CallsView()
                case .contacts: ContactsView()
                case .messages: MessagesView()
                case .sms: SMSView()
                case .team: TeamView()
                case .calendar: CalendarView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showAccount) { AccountSheet() }
        .onChange(of: deepLinks.pending) { link in
            if link != nil { tab = .calls }
        }
    }
}
