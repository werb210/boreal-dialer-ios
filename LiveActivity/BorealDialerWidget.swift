import SwiftUI
import WidgetKit

struct BorealDialerEntry: TimelineEntry {
    let date: Date
    let contacts: [WidgetContact]
    // BOREAL_DIALER_LARGE_WIDGET_v685 - missed calls, today's count, next tasks, next meeting.
    var dashboard: DialerDashboard = .empty
    var meetingTitle: String? = nil
    var meetingAt: Date? = nil
    var isBusy: Bool = false // BOREAL_DIALER_v823_WIDGET_ACTIONS
}

struct BorealDialerProvider: TimelineProvider {
    func placeholder(in context: Context) -> BorealDialerEntry {
        BorealDialerEntry(date: Date(), contacts: [WidgetContact(name: "Recent contact", number: "+14035550123")])
    }

    func getSnapshot(in context: Context, completion: @escaping (BorealDialerEntry) -> Void) { completion(entry()) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BorealDialerEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func entry() -> BorealDialerEntry {
        let meeting = WatchSnapshotSync.nextMeeting()
        return BorealDialerEntry(date: Date(), contacts: WidgetSnapshotStore.load().contacts,
                                 dashboard: DialerDashboardStore.load(),
                                 meetingTitle: meeting?.title, meetingAt: meeting?.startsAt,
                                 isBusy: StaffWidgetActionStore.isBusy) // BOREAL_DIALER_v823_WIDGET_ACTIONS
    }
}

// BOREAL_DIALER_v817_WIDGET - the home-screen widget is a sibling of the client app's widget
// (client-app/ios/App/ClientWidget/ClientWidget.swift): the same navy card, white / grey / gold
// palette, SF Symbol mountain mark and caps labels. Lock-screen (accessory) families stay
// system-styled. Every value below is checked against the navy for contrast: white (15:1),
// grey = white at 0.6 (about 6.7:1), gold (about 7:1), red (about 6:1).
enum DialerWidgetPalette {
    // Same values as the client widget's borealNavy / borealGold.
    static let navy = Color(red: 11 / 255, green: 31 / 255, blue: 58 / 255)
    static let gold = Color(red: 201 / 255, green: 162 / 255, blue: 74 / 255)
    static let red = Color(red: 1.0, green: 107 / 255, blue: 107 / 255)
    static let green = Color(red: 74 / 255, green: 222 / 255, blue: 128 / 255) // BOREAL_DIALER_v823_WIDGET_ACTIONS
    static let text = Color.white
    static let muted = Color.white.opacity(0.6)
}

struct BorealDialerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BorealDialerEntry

    private var newCallURL: URL { URL(string: "borealdialer://new-call")! }

    var body: some View {
        switch family {
        case .systemLarge:
            largeView
        case .accessoryCircular:
            Link(destination: URL(string: "borealdialer://new-call")!) {
                VStack(spacing: 2) {
                    Image(systemName: "phone.fill")
                    Text("Boreal").font(.system(size: 9, weight: .semibold))
                }
            }
            .widgetURL(URL(string: "borealdialer://new-call"))
        case .accessoryRectangular:
            if let contact = entry.contacts.first {
                Link(destination: callURL(contact.number)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Call next recent", systemImage: "phone.fill").font(.headline)
                        Text(contact.name).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .widgetURL(callURL(contact.number))
            } else {
                Link(destination: URL(string: "borealdialer://new-call")!) {
                    Label("Open Boreal Dialer", systemImage: "phone.fill")
                }
                .widgetURL(URL(string: "borealdialer://new-call"))
            }
        case .systemSmall:
            smallView
        default:
            mediumView
        }
    }

    // MARK: - Shared pieces (BOREAL_DIALER_v817_WIDGET - mirrors the client widget's BrandRow)

    private var callsTodayText: String {
        entry.dashboard.callsToday == 1 ? "1 call today" : "\(entry.dashboard.callsToday) calls today"
    }

    private var brandRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "mountain.2.fill").font(.caption.bold())
            Text("Boreal Dialer").font(.caption.bold()).lineLimit(1)
        }
        .foregroundStyle(DialerWidgetPalette.text)
    }

    /// Logo + "Boreal Dialer", today's call count right-aligned in muted text.
    private var headerRow: some View {
        HStack(spacing: 6) {
            brandRow
            Spacer(minLength: 4)
            Text(callsTodayText)
                .font(.caption)
                .foregroundStyle(DialerWidgetPalette.muted)
                .lineLimit(1)
            presenceButton
        }
    }

    /// BOREAL_DIALER_v823_WIDGET_ACTIONS - one tap switches Available / Busy without opening the app (iOS 17+).
    @ViewBuilder
    private var presenceButton: some View {
        if #available(iOS 17.0, *) {
            Button(intent: SetBorealBusyIntent(busy: !entry.isBusy)) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.isBusy ? DialerWidgetPalette.red : DialerWidgetPalette.green)
                        .frame(width: 6, height: 6)
                    Text(entry.isBusy ? "Busy" : "Available")
                        .font(.caption2.bold())
                        .foregroundStyle(DialerWidgetPalette.text)
                        .lineLimit(1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isBusy ? "Busy. Tap to become available" : "Available. Tap to become busy")
        }
    }

    /// BOREAL_DIALER_v823_WIDGET_ACTIONS - a task row with a tick box that completes the task (iOS 17+).
    @ViewBuilder
    private func taskRow(_ item: DashboardItem) -> some View {
        if #available(iOS 17.0, *), let taskId = item.taskId {
            HStack(spacing: 6) {
                Button(intent: CompleteBorealTaskIntent(taskId: taskId)) {
                    Image(systemName: "circle")
                        .font(.caption.bold())
                        .foregroundStyle(DialerWidgetPalette.gold)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark \(item.title) done")
                Text(item.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DialerWidgetPalette.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(DialerWidgetPalette.muted)
                    .lineLimit(1)
            }
        } else {
            row(icon: "checklist", iconColor: DialerWidgetPalette.gold, title: item.title, detail: item.detail)
        }
    }

    /// The client widget's caps label ("STAGE").
    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(DialerWidgetPalette.muted)
            .lineLimit(1)
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(DialerWidgetPalette.muted)
            .lineLimit(1)
    }

    /// The gold action line, styled like the client's "Fill in 3 forms".
    private var newCallLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "phone.fill")
            Text("New call").lineLimit(1)
        }
        .font(.subheadline.bold())
        .foregroundStyle(DialerWidgetPalette.gold)
    }

    private var newCallLink: some View {
        Link(destination: newCallURL) {
            newCallLine.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "2 missed" in red when there are missed calls; nothing otherwise.
    private var missedBadge: some View {
        let count = entry.dashboard.missed.count
        return Text(count == 1 ? "1 missed" : "\(count) missed")
            .font(.caption.bold())
            .foregroundStyle(DialerWidgetPalette.red)
            .lineLimit(1)
            .opacity(count > 0 ? 1 : 0)
    }

    private func row(icon: String, iconColor: Color, title: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(iconColor)
                .frame(width: 16)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DialerWidgetPalette.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(detail)
                .font(.caption)
                .foregroundStyle(DialerWidgetPalette.muted)
                .lineLimit(1)
        }
    }

    private func contactRow(_ contact: WidgetContact) -> some View {
        Link(destination: callURL(contact.number)) {
            row(icon: "phone.fill", iconColor: DialerWidgetPalette.gold, title: contact.name, detail: "")
        }
    }

    // MARK: - Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            brandRow
            Text(callsTodayText)
                .font(.caption)
                .foregroundStyle(DialerWidgetPalette.muted)
                .lineLimit(1)
            if entry.contacts.isEmpty {
                emptyText("No recent calls")
            } else {
                ForEach(Array(entry.contacts.prefix(2).enumerated()), id: \.offset) { _, contact in
                    Text(contact.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DialerWidgetPalette.text)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            newCallLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .legacyWidgetPadding()
        // A small widget is one tap target: it opens the keypad, as before.
        .widgetURL(newCallURL)
    }

    // MARK: - Medium

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
            sectionTitle("Recent calls").padding(.top, 4)
            if entry.contacts.isEmpty {
                emptyText("No recent calls")
            } else {
                // Two rows: the header, label and action line need the rest of the medium height.
                ForEach(Array(entry.contacts.prefix(2).enumerated()), id: \.offset) { _, contact in
                    contactRow(contact)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                newCallLink
                missedBadge
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .legacyWidgetPadding()
        .widgetURL(newCallURL)
    }

    // MARK: - Large (BOREAL_DIALER_LARGE_WIDGET_v685, restyled v817)

    /// BOREAL_DIALER_v817_WIDGET - one recent row when missed calls and tasks already fill
    /// most of the large height, two otherwise, so nothing is clipped.
    private var recentLimit: Int {
        entry.dashboard.missed.prefix(3).count + entry.dashboard.tasks.prefix(3).count >= 5 ? 1 : 2
    }

    // BOREAL_DIALER_v817_WIDGET - sections are compact groups; the Spacers sit only between
    // groups so the free height is shared out instead of pooling at the bottom.
    private var largeView: some View {
        let d = entry.dashboard
        return VStack(alignment: .leading, spacing: 0) {
            headerRow
            newCallLink.padding(.top, 8)

            Spacer(minLength: 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    sectionTitle("Missed calls")
                    Spacer(minLength: 4)
                    missedBadge
                }
                if d.missed.isEmpty {
                    emptyText("No missed calls")
                } else {
                    ForEach(Array(d.missed.prefix(3).enumerated()), id: \.offset) { _, item in
                        Link(destination: item.number.map { callURL($0) } ?? newCallURL) {
                            row(icon: "phone.arrow.down.left", iconColor: DialerWidgetPalette.red,
                                title: item.title, detail: item.detail)
                        }
                    }
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .leading, spacing: 3) {
                sectionTitle("Next up")
                if d.tasks.isEmpty {
                    emptyText("No tasks due today")
                } else {
                    ForEach(Array(d.tasks.prefix(3).enumerated()), id: \.offset) { _, item in
                        taskRow(item) // BOREAL_DIALER_v823_WIDGET_ACTIONS
                    }
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .leading, spacing: 3) {
                sectionTitle("Next meeting")
                if let title = entry.meetingTitle, let at = entry.meetingAt {
                    row(icon: "calendar", iconColor: DialerWidgetPalette.gold,
                        title: title, detail: DialerDashboardStore.time(at))
                } else {
                    emptyText("Nothing scheduled")
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .leading, spacing: 3) {
                sectionTitle("Recent calls")
                if entry.contacts.isEmpty {
                    emptyText("No recent calls")
                } else {
                    ForEach(Array(entry.contacts.prefix(recentLimit).enumerated()), id: \.offset) { _, contact in
                        contactRow(contact)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .legacyWidgetPadding()
    }

    private func callURL(_ number: String) -> URL {
        var components = URLComponents()
        components.scheme = "borealdialer"
        components.host = "call"
        components.queryItems = [URLQueryItem(name: "number", value: number)]
        return components.url!
    }
}

struct BorealDialerWidget: Widget {
    let kind = "BorealDialerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BorealDialerProvider()) { entry in
            BorealDialerWidgetView(entry: entry).dialerWidgetBackground()
        }
        .configurationDisplayName("Boreal Dialer")
        .description("Start a call, call back a missed call, and see what is next.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular]) // BOREAL_DIALER_LARGE_WIDGET_v685
    }
}

// BOREAL_DIALER_v817_WIDGET - picks the background per family: the navy card on the home
// screen (as the client widget), the system background on the lock screen.
struct DialerWidgetBackground<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    let content: Content

    private var isAccessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
        default: return false
        }
    }

    var body: some View {
        if isAccessory {
            if #available(iOSApplicationExtension 17.0, *) {
                content.containerBackground(.background, for: .widget)
            } else {
                content
            }
        } else {
            if #available(iOSApplicationExtension 17.0, *) {
                content.containerBackground(DialerWidgetPalette.navy, for: .widget)
            } else {
                // Before iOS 17 the widget paints its own background (legacyWidgetPadding pads the content).
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DialerWidgetPalette.navy)
            }
        }
    }
}

// BOREAL_DIALER_v532 - iOS 17+ requires every widget to declare its background.
extension View {
    // BOREAL_DIALER_v817_WIDGET - navy containerBackground for home-screen families (see DialerWidgetBackground).
    func dialerWidgetBackground() -> some View {
        DialerWidgetBackground(content: self)
    }

    /// iOS 17+ adds content margins itself; before that the widget pads its own content.
    @ViewBuilder
    func legacyWidgetPadding() -> some View {
        if #available(iOSApplicationExtension 17.0, *) { self } else { padding() }
    }
}
