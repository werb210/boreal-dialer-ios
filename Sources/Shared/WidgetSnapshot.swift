import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct WidgetContact: Codable, Equatable {
    let name: String
    let number: String
}

struct WidgetSnapshot: Codable, Equatable {
    let contacts: [WidgetContact]
    let updatedAt: Date
}

enum WidgetSnapshotStore {
    static let appGroup = "group.financial.boreal.dialer"
    private static let snapshotKey = "widget.recentContacts.v1"

    static func load() -> WidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot(contacts: [], updatedAt: .distantPast)
        }
        return snapshot
    }

    /// Rewrites the last snapshot when the app enters the foreground. This is
    /// deliberately local-only: opening the app never triggers a widget fetch.
    static func refreshStoredSnapshot() {
        save(load().contacts)
    }

    static func save(_ contacts: [WidgetContact]) {
        let snapshot = WidgetSnapshot(contacts: Array(contacts.prefix(3)), updatedAt: Date())
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "BorealDialerWidget")
#endif
    }
}
