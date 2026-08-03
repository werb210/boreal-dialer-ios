import SwiftUI

// boreal-dialer-ios v4 — top tab strip: Calls / Messages / SMS / Team / Notifications.
struct RootTabView: View {
    enum Tab: String, CaseIterable {
        // BOREAL_DIALER_CONTACTS_TAB_v7
        // BOREAL_DIALER_CALENDAR_TAB_v8 - the six tabs from the concept mockup.
        case calls = "Calls", contacts = "Contacts", messages = "Messages",
             sms = "SMS", team = "Team", calendar = "Calendar"
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
                                // BOREAL_DIALER_THEME_v27
                        Text(t.rawValue)
                            .font(.system(size: 13.5, weight: .semibold))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 9)
                            .background(
                                Capsule().fill(tab == t ? Theme.green : Color.clear)
                            )
                            .overlay(
                                Capsule().stroke(tab == t ? Color.clear : Theme.line2, lineWidth: 1)
                            )
                            .foregroundColor(tab == t ? Theme.onGreen : Theme.muted)
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
    }
}
