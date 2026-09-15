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

    private func snapshotEntry() -> BorealWatchEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        return BorealWatchEntry(
            date: Date(),
            status: defaults?.string(forKey: "presence.status") ?? "away",
            missedCalls: defaults?.integer(forKey: "calls.missed") ?? 0,
            tasksDue: defaults?.integer(forKey: "tasks.due") ?? 0,
            meeting: WatchSnapshotSync.nextMeeting()
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

@main
struct BorealWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BorealWatchWidget", provider: BorealWatchProvider()) { entry in
            BorealWatchWidgetView(entry: entry)
        }
        .configurationDisplayName("Boreal")
        .description("Your availability and missed calls.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}
