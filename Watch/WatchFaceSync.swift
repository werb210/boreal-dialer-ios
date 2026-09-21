// BOREAL_DIALER_WATCH_FACE_v371
// The complications read presence.status / calls.missed / tasks.due from the
// app group. Until now only the iPhone wrote those keys - into the iPhone's own
// app group, which is on a different device - so every Watch face showed the
// fallback forever. The Watch now fetches GET /api/watch/face with its own
// Watch session and writes its own app group.
import Foundation
import WatchKit
import WidgetKit

enum WatchFaceSync {
    static let appGroup = "group.financial.boreal.dialer"
    static let refreshTaskID = "boreal.face"

    struct Face: Decodable, Equatable {
        let status: String
        let missedCalls: Int
        let tasksDue: Int
    }

    static func refresh(client supplied: WatchAPIClient? = nil) async {
        guard let client = supplied ?? (try? WatchAPIClient()) else { return }
        guard await client.auth.session != nil else { return }
        guard let data = try? await client.request(path: "/watch/face"),
              let face = try? JSONDecoder().decode(Face.self, from: data) else { return }
        publish(face)
    }

    static func publish(_ face: Face) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        defaults.set(face.status, forKey: "presence.status")
        defaults.set(face.missedCalls, forKey: "calls.missed")
        defaults.set(face.tasksDue, forKey: "tasks.due")
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Keeps the face fresh while the app is closed. watchOS decides the real
    /// time; 15 minutes is the preferred cadence.
    static func scheduleNext() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date().addingTimeInterval(15 * 60),
            userInfo: refreshTaskID as NSString
        ) { _ in }
    }
}

/// Complication taps arrive as borealwatch://<target>. Only known targets route.
enum WatchComplicationLink {
    static let targets: Set<String> = ["dial", "recents"]
    static func target(for url: URL) -> String? {
        guard url.scheme == "borealwatch", let host = url.host, targets.contains(host) else { return nil }
        return host
    }
}
