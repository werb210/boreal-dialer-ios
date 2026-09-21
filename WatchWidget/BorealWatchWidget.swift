// BOREAL_DIALER_BLOCK_v210_WATCH_PHASE2_v1
// Complication + Smart Stack entry. Reads the shared app-group snapshot the
// Watch app writes, so the widget never makes a network call of its own.
import WidgetKit
import SwiftUI

struct BorealWatchEntry: TimelineEntry {
    let date: Date
    let status: String
    let missedCalls: Int
    // BOREAL_DIALER_WATCH_SNAPSHOT_WRITER_v210
    let tasksDue: Int
    // BOREAL_DIALER_WATCH_NEXT_MEETING_v211
    let meeting: (title: String, startsAt: Date)?
}

struct BorealWatchProvider: TimelineProvider {
    private let appGroup = "group.financial.boreal.dialer"

    // BOREAL_DIALER_WIDGET_SELF_CONTAINED_v226
    // Read straight from the app group because this target compiles only
    // WatchWidget/. The keys are the contract with the publishing app target.
    private static func nextMeeting(from defaults: UserDefaults?) -> (title: String, startsAt: Date)? {
        guard let defaults,
              let title = defaults.string(forKey: "meeting.next.title") else { return nil }
        let at = defaults.double(forKey: "meeting.next.at")
        guard at > 0 else { return nil }
        let date = Date(timeIntervalSince1970: at)
        // Expire on read because the face can render long after the phone last
        // published, and a meeting in the past is no longer the next thing due.
        guard date > Date() else { return nil }
        return (title, date)
    }

    private func snapshotEntry() -> BorealWatchEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        return BorealWatchEntry(
            date: Date(),
            status: defaults?.string(forKey: "presence.status") ?? "away",
            missedCalls: defaults?.integer(forKey: "calls.missed") ?? 0,
            tasksDue: defaults?.integer(forKey: "tasks.due") ?? 0,
            meeting: Self.nextMeeting(from: defaults)
        )
    }

    func placeholder(in context: Context) -> BorealWatchEntry {
        BorealWatchEntry(date: Date(), status: "available", missedCalls: 0, tasksDue: 0, meeting: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BorealWatchEntry) -> Void) {
        completion(snapshotEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BorealWatchEntry>) -> Void) {
        // Refresh on a fixed cadence; the app pushes reloadAllTimelines on change.
        completion(Timeline(entries: [snapshotEntry()], policy: .after(Date().addingTimeInterval(900))))
    }
}

struct BorealWatchWidgetView: View {
    // BOREAL_DIALER_WATCH_NEXT_MEETING_v211 - one formatter, not one per render.
    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    @Environment(\.widgetFamily) private var family
    let entry: BorealWatchEntry

    private var symbol: String {
        switch entry.status {
        case "available": return "phone.circle.fill"
        case "on_call": return "phone.connection.fill"
        case "busy": return "phone.down.fill" // BOREAL_DIALER_WATCH_FACE_v371 - server status set is available|busy|offline
        default: return "moon.zzz.fill"
        }
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack { AccessoryWidgetBackground(); Image(systemName: symbol) }
        case .accessoryInline:
            Label(entry.status.replacingOccurrences(of: "_", with: " "), systemImage: symbol)
        default:
            HStack(spacing: 6) {
                Image(systemName: symbol)
                VStack(alignment: .leading) {
                    Text(entry.status.replacingOccurrences(of: "_", with: " ")).font(.headline)
                    if entry.missedCalls > 0 {
                        Text("\(entry.missedCalls) missed").font(.caption).foregroundStyle(.secondary)
                    }
                    // BOREAL_DIALER_WATCH_NEXT_MEETING_v211 - the next thing on
                    // the clock outranks a count of things with no time attached.
                    if let meeting = entry.meeting {
                        Text("\(Self.clock.string(from: meeting.startsAt))  \(meeting.title)")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    // BOREAL_DIALER_WATCH_SNAPSHOT_WRITER_v210
                    if entry.tasksDue > 0 {
                        Text("\(entry.tasksDue) due").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct BorealWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BorealWatchWidget", provider: BorealWatchProvider()) { entry in
            BorealWatchWidgetView(entry: entry).borealWidgetBackground()
        }
        .configurationDisplayName("Boreal")
        .description("Your availability and missed calls.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

// BOREAL_DIALER_WATCH_COMPLICATIONS_v371
// watchOS 10 shows a "please adopt containerBackground" notice instead of a widget
// that does not declare one; every Boreal widget goes through this helper.
extension View {
    func borealWidgetBackground() -> some View {
        containerBackground(for: .widget) { Color.clear }
    }
}

/// One tap from the watch face to the dial pad.
struct BorealDialWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BorealDialWidget", provider: BorealWatchProvider()) { _ in
            BorealDialWidgetView()
                .widgetURL(URL(string: "borealwatch://dial"))
                .borealWidgetBackground()
        }
        .configurationDisplayName("Boreal Dial")
        .description("Open the Boreal dial pad.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct BorealDialWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: "phone.fill").font(.title3).widgetLabel("Dial")
        default:
            ZStack { AccessoryWidgetBackground(); Image(systemName: "phone.fill").font(.title3) }
        }
    }
}

/// Today's missed calls; tap opens Recent Calls.
struct BorealMissedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BorealMissedWidget", provider: BorealWatchProvider()) { entry in
            BorealMissedWidgetView(entry: entry)
                .widgetURL(URL(string: "borealwatch://recents"))
                .borealWidgetBackground()
        }
        .configurationDisplayName("Boreal Missed Calls")
        .description("Missed calls today.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct BorealMissedWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BorealWatchEntry
    var body: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: "phone.arrow.down.left").font(.title3).widgetLabel("\(entry.missedCalls) missed")
        case .accessoryInline:
            Label("\(entry.missedCalls) missed", systemImage: "phone.arrow.down.left")
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "phone.arrow.down.left").font(.caption2)
                    Text("\(entry.missedCalls)").font(.title3.bold())
                }
            }
        }
    }
}

@main
struct BorealWatchWidgets: WidgetBundle {
    var body: some Widget {
        BorealWatchWidget()
        BorealDialWidget()
        BorealMissedWidget()
    }
}
