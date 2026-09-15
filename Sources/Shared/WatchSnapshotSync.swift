// BOREAL_DIALER_WATCH_SNAPSHOT_WRITER_v210
// Fetches GET /api/watch/snapshot and writes it into the shared app group.
//
// The Watch complication has always read presence.status and calls.missed from
// that group, and until now nothing wrote them - BorealWatchWidget.swift falls
// back to "away" and 0, which is exactly what every watch face has shown since
// the complication shipped. BF_SERVER_WATCH_SNAPSHOT_v1 was built to serve this
// call and had no client.
//
// The server returns tasksDue as of v209.
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct WatchSnapshot: Codable, Equatable {
    let status: String
    let missedCalls: Int
    let tasksDue: Int

    // tasksDue predates no client, so decode it leniently: an older server that
    // does not send it must not fail the whole snapshot and leave the
    // complication stale.
    private enum CodingKeys: String, CodingKey {
        case status, missedCalls, tasksDue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = (try? c.decode(String.self, forKey: .status)) ?? "away"
        missedCalls = (try? c.decode(Int.self, forKey: .missedCalls)) ?? 0
        tasksDue = (try? c.decode(Int.self, forKey: .tasksDue)) ?? 0
    }

    init(status: String, missedCalls: Int, tasksDue: Int) {
        self.status = status
        self.missedCalls = missedCalls
        self.tasksDue = tasksDue
    }
}

enum WatchSnapshotSync {
    // Must match the keys BorealWatchWidget.swift reads. Changing either side
    // alone silently returns the complication to its fallback values, which is
    // how this went unnoticed for so long.
    private static let statusKey = "presence.status"
    private static let missedKey = "calls.missed"
    private static let tasksKey = "tasks.due"
    // BOREAL_DIALER_WATCH_NEXT_MEETING_v211
    private static let meetingTitleKey = "meeting.next.title"
    private static let meetingAtKey = "meeting.next.at"

    // BOREAL_DIALER_WATCH_SNAPSHOT_TARGET_SPLIT_v217
    // refresh() lived here and called the app's networking client. This file is
    // compiled into BorealDialerLiveActivity too, where Sources/Networking and
    // that client do not exist. The fetch now lives in
    // Sources/Networking/WatchSnapshotFetch.swift, which only the app target
    // compiles. Everything below is pure UserDefaults and is safe everywhere.

    static func publish(_ snapshot: WatchSnapshot) {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroup) else { return }
        defaults.set(snapshot.status, forKey: statusKey)
        defaults.set(snapshot.missedCalls, forKey: missedKey)
        defaults.set(snapshot.tasksDue, forKey: tasksKey)
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "BorealWatchWidget")
#endif
    }

    // BOREAL_DIALER_WATCH_NEXT_MEETING_v211
    // Calendar events are proxied from Microsoft Graph per request, so there is
    // no meetings table the /watch/snapshot query could read. Rather than put a
    // Graph round trip - and an O365 token that can expire - behind a watch face,
    // the phone publishes the next meeting when it already has the agenda in hand.
    //
    // Publishing nil clears the keys. A stale meeting on a watch face is worse
    // than an empty one: it is read as the next thing due.
    static func publishNextMeeting(title: String?, startsAt: Date?) {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroup) else { return }
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty, let startsAt, startsAt > Date() {
            defaults.set(trimmed, forKey: meetingTitleKey)
            defaults.set(startsAt.timeIntervalSince1970, forKey: meetingAtKey)
        } else {
            defaults.removeObject(forKey: meetingTitleKey)
            defaults.removeObject(forKey: meetingAtKey)
        }
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "BorealWatchWidget")
#endif
    }

    /// The published meeting, or nil once it has started or if none was set.
    static func nextMeeting() -> (title: String, startsAt: Date)? {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroup),
              let title = defaults.string(forKey: meetingTitleKey) else { return nil }
        let at = defaults.double(forKey: meetingAtKey)
        guard at > 0 else { return nil }
        let date = Date(timeIntervalSince1970: at)
        // Expire on read as well as on write: the face can render long after the
        // phone last published, and a meeting in the past must not be shown.
        guard date > Date() else { return nil }
        return (title, date)
    }

    /// What the complication currently shows, for anything that needs to render
    /// the same numbers without waiting on the network.
    static func lastPublished() -> WatchSnapshot {
        let defaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroup)
        return WatchSnapshot(
            status: defaults?.string(forKey: statusKey) ?? "away",
            missedCalls: defaults?.integer(forKey: missedKey) ?? 0,
            tasksDue: defaults?.integer(forKey: tasksKey) ?? 0
        )
    }
}
