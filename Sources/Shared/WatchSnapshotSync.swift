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

    /// Pulls the snapshot and publishes it. Never throws: a failed refresh must
    /// leave the last good values in place rather than blanking the face.
    @discardableResult
    static func refresh() async -> WatchSnapshot? {
        do {
            let request = try APIClient.shared.makeRequest(path: "/watch/snapshot", method: "GET")
            let data = try await APIClient.shared.makeAuthorizedRequest(request)
            let snapshot = try JSONDecoder().decode(WatchSnapshot.self, from: data)
            publish(snapshot)
            return snapshot
        } catch {
            return nil
        }
    }

    static func publish(_ snapshot: WatchSnapshot) {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroup) else { return }
        defaults.set(snapshot.status, forKey: statusKey)
        defaults.set(snapshot.missedCalls, forKey: missedKey)
        defaults.set(snapshot.tasksDue, forKey: tasksKey)
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "BorealWatchWidget")
#endif
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
