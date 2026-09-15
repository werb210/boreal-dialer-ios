// BOREAL_DIALER_WATCH_SNAPSHOT_TARGET_SPLIT_v217
// The network half of the watch snapshot.
//
// This file is deliberately in Sources/Networking rather than Sources/Shared.
// project.yml compiles Sources/Shared into BorealDialerLiveActivity as well as
// the app, and extensions do not get Sources/Networking - so anything in Shared
// that touches APIClient fails to compile the extension. That is exactly what
// v210 did.
//
// Keep it that way: the publish/read side stays shared because the widget needs
// it; the fetch stays app-only because only the app can authenticate.
import Foundation

extension WatchSnapshotSync {
    /// Pulls GET /api/watch/snapshot and publishes it to the app group.
    /// Never throws: a failed refresh must leave the last good values in place
    /// rather than blanking the watch face.
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
}
