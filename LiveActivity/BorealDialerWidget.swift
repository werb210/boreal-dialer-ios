import SwiftUI
import WidgetKit

struct BorealDialerEntry: TimelineEntry {
    let date: Date
    let contacts: [WidgetContact]
}

struct BorealDialerProvider: TimelineProvider {
    func placeholder(in context: Context) -> BorealDialerEntry {
        BorealDialerEntry(date: Date(), contacts: [
            WidgetContact(name: "Recent contact", number: "+14035550123")
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (BorealDialerEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BorealDialerEntry>) -> Void) {
        let current = entry()
        completion(Timeline(entries: [current], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func entry() -> BorealDialerEntry {
        BorealDialerEntry(date: Date(), contacts: WidgetSnapshotStore.load().contacts)
    }
}

struct BorealDialerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BorealDialerEntry

    var body: some View {
        switch family {
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
            .padding()
        }
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
            BorealDialerWidgetView(entry: entry)
        }
        .configurationDisplayName("Boreal Dialer")
        .description("Start a new call or call a recent contact.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
