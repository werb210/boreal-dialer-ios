import SwiftUI
import WidgetKit

struct BorealDialerEntry: TimelineEntry {
    let date: Date
    let contacts: [WidgetContact]
    // BOREAL_DIALER_LARGE_WIDGET_v685 - missed calls, today's count, next tasks, next meeting.
    var dashboard: DialerDashboard = .empty
    var meetingTitle: String? = nil
    var meetingAt: Date? = nil
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
                                 meetingTitle: meeting?.title, meetingAt: meeting?.startsAt)
    }
}

struct BorealDialerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BorealDialerEntry

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
        default:
            VStack(alignment: .leading, spacing: 7) {
                Link(destination: URL(string: "borealdialer://new-call")!) {
                    Label("New call", systemImage: "phone.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .widgetURL(URL(string: "borealdialer://new-call"))

                ForEach(Array(entry.contacts.prefix(family == .systemSmall ? 2 : 3).enumerated()), id: \.offset) { _, contact in
                    Link(destination: callURL(contact.number)) {
                        HStack {
                            Text(contact.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "phone.circle.fill")
                        }.font(.subheadline)
                    }
                    .widgetURL(callURL(contact.number))
                }
                Spacer(minLength: 0)
            }
            .legacyWidgetPadding()
        }
    }

    // BOREAL_DIALER_LARGE_WIDGET_v685
    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }

    private var largeView: some View {
        let d = entry.dashboard
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Link(destination: URL(string: "borealdialer://new-call")!) {
                    Label("New call", systemImage: "phone.fill").font(.headline)
                }
                Spacer()
                Text(d.callsToday == 1 ? "1 call today" : "\(d.callsToday) calls today")
                    .font(.caption).foregroundStyle(.secondary)
            }
            sectionTitle("Missed calls")
            if d.missed.isEmpty { Text("None").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(Array(d.missed.enumerated()), id: \.offset) { _, item in
                Link(destination: item.number.map { callURL($0) } ?? URL(string: "borealdialer://new-call")!) {
                    HStack {
                        Image(systemName: "phone.arrow.down.left").foregroundStyle(.red)
                        Text(item.title).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                    }.font(.subheadline)
                }
            }
            sectionTitle("Next up")
            if d.tasks.isEmpty { Text("No tasks due today").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(Array(d.tasks.enumerated()), id: \.offset) { _, item in
                HStack {
                    Image(systemName: "checklist")
                    Text(item.title).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.font(.subheadline)
            }
            sectionTitle("Next meeting")
            if let title = entry.meetingTitle, let at = entry.meetingAt {
                HStack {
                    Image(systemName: "calendar")
                    Text(title).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(DialerDashboardStore.time(at)).font(.caption).foregroundStyle(.secondary)
                }.font(.subheadline)
            } else {
                Text("Nothing scheduled").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
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

// BOREAL_DIALER_v532 - iOS 17+ requires every widget to declare its background.
extension View {
    @ViewBuilder
    func dialerWidgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) { containerBackground(.background, for: .widget) } else { self }
    }

    /// iOS 17+ adds content margins itself; before that the widget pads its own content.
    @ViewBuilder
    func legacyWidgetPadding() -> some View {
        if #available(iOSApplicationExtension 17.0, *) { self } else { padding() }
    }
}
