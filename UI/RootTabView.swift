import SwiftUI

// boreal-dialer-ios v4 - top tab strip: Calls / Contacts / SMS / Messages / Team / Calendar.
struct RootTabView: View {
    // BOREAL_DIALER_ACCOUNT_SHEET_v42
    // BOREAL_DIALER_v803_UI - the account button no longer sits at the end of
    // the rail (it crowded Team and Calendar off-screen); it lives in the Calls
    // header next to Keypad / Recents / Voicemail.

    enum Tab: String, CaseIterable {
        // BOREAL_DIALER_CONTACTS_TAB_v7
        // BOREAL_DIALER_CALENDAR_TAB_v8 - the six tabs from the concept mockup.
        // BOREAL_DIALER_v817_MESSAGING - same order as the portal's Communications tabs:
        // SMS (texts), Messages (client-portal chats), Team (staff chat).
        case calls = "Calls", contacts = "Contacts", sms = "SMS",
             messages = "Messages", team = "Team", calendar = "Calendar"
    }

    @State private var tab: Tab = .calls
    @ObservedObject private var deepLinks = DeepLinkCoordinator.shared
    // BOREAL_DIALER_v803_UI - drives the green dot on the Messages pill.
    @ObservedObject private var inbox = InboxUnreadStore.shared
    // BOREAL_DIALER_v820_WATCH - a tapped alert push picks the tab; the tab itself opens the thread.
    @ObservedObject private var alerts = AlertNavigator.shared
    // BOREAL_DIALER_v823_ACTIONS - Voice Note / Next Follow-up from the controls, Action Button and Siri.
    @ObservedObject private var actions = StaffActionRouter.shared

    var body: some View {
        VStack(spacing: 0) {
            OfflineStatusBar() // BOREAL_DIALER_OFFLINE_v303
            // BOREAL_DIALER_MOCKUP_LAYOUT_v60 - mockup tab strip: pills sized to their
            // text, 8 pt apart, semibold.
            // BOREAL_DIALER_v803_UI - just the six pills, horizontally scrollable,
            // and the selected pill is scrolled into view.
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Tab.allCases, id: \.self) { t in
                            Button {
                                tab = t
                            } label: {
                                tabPill(t)
                            }
                            .buttonStyle(.plain)
                            .id(t)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                }
                .onChange(of: tab) { selected in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(selected, anchor: .center)
                    }
                }
            }
            Rectangle().fill(Theme.line).frame(height: 1)

            Group {
                switch tab {
                // BOREAL_DIALER_CALLS_TAB_v11 - Keypad / Recents / Voicemail.
                case .calls: CallsView()
                case .contacts: ContactsView()
                case .sms: SMSView()
                case .messages: MessagesView()
                case .team: TeamView()
                case .calendar: CalendarView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: deepLinks.pending) { link in
            if link != nil { tab = .calls }
        }
        // BOREAL_DIALER_v820_WATCH - onReceive also delivers a value set before this view existed (cold launch from a tap).
        .onReceive(alerts.$pending) { destination in
            if let destination { tab = destination.tab }
        }
        // BOREAL_DIALER_v803_MENTIONS - keep the Team socket open on every tab so
        // an @mention can raise a local alert while the Team tab is not showing.
        .task {
            TeamStore.shared.connect()
            await TeamStore.shared.loadUsers()
        }
        // Signed out: RootTabView goes away, and so does the socket.
        .onDisappear { TeamStore.shared.disconnect() }
        // BOREAL_DIALER_v823_ACTIONS
        .sheet(item: $actions.voiceNote) { target in
            VoiceNoteSheet(target: target)
        }
        .alert("Boreal", isPresented: Binding(
            get: { actions.message != nil },
            set: { if !$0 { actions.message = nil } }
        )) {
            Button("OK", role: .cancel) { actions.message = nil }
        } message: {
            Text(actions.message ?? "")
        }
        // BOREAL_DIALER_v803_UI - unread dot for Messages, refreshed every two minutes.
        .task {
            while !Task.isCancelled {
                await inbox.refresh()
                try? await Task.sleep(nanoseconds: 120_000_000_000)
            }
        }
    }

    // BOREAL_DIALER_v803_UI - the mockup's .tab pill: 13.5pt semibold, 9x15,
    // capsule; the active pill is solid green with dark text.
    private func tabPill(_ t: Tab) -> some View {
        let active = tab == t
        return HStack(spacing: 7) {
            Text(t.rawValue)
                .font(.system(size: 13.5, weight: .semibold))
            if t == .messages && inbox.hasUnread {
                Circle()
                    .fill(active ? Theme.onGreen : Theme.greenBright)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Unread")
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .background(Capsule().fill(active ? Theme.green : Color.clear))
        .overlay(Capsule().stroke(active ? Theme.green : Theme.line2, lineWidth: 1))
        .foregroundColor(active ? Theme.onGreen : Theme.muted)
        .contentShape(Capsule())
    }
}
