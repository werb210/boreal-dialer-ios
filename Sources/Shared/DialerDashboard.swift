// BOREAL_DIALER_LARGE_WIDGET_v685 - what the large home-screen widget shows: missed calls,
// today's call count and the next tasks / callbacks. The app writes it (DialerDashboardFetch)
// whenever it comes to the front; the next meeting comes from WatchSnapshotSync.
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct DashboardItem: Codable, Equatable {
    let title: String
    let detail: String
    let number: String?
}

struct DialerDashboard: Codable, Equatable {
    var missed: [DashboardItem]
    var callsToday: Int
    var tasks: [DashboardItem]
    var updatedAt: Date

    static let empty = DialerDashboard(missed: [], callsToday: 0, tasks: [], updatedAt: .distantPast)
}

enum DialerDashboardStore {
    private static let key = "widget.dashboard.v1"

    static func load() -> DialerDashboard {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroup),
              let data = defaults.data(forKey: key),
              let dashboard = try? JSONDecoder().decode(DialerDashboard.self, from: data) else { return .empty }
        return dashboard
    }

    static func save(_ dashboard: DialerDashboard) {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroup),
              let data = try? JSONEncoder().encode(dashboard) else { return }
        defaults.set(data, forKey: key)
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "BorealDialerWidget")
#endif
    }

    /// Server timestamps come with or without fractional seconds.
    static func date(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(date) ? "h:mm a" : "MMM d, h:mm a"
        return f.string(from: date)
    }
}
