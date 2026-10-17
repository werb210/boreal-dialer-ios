// BOREAL_DIALER_v821 - which Boreal alerts show while a Focus with the "Boreal Dialer" Focus filter is on.
//   "All Boreal alerts"             - everything (also what applies when no Focus filter is active).
//   "Only client calls and messages" - missed calls, voicemail, texts, client-portal messages and handoffs; internal
//                                      alerts (Team @mentions, Team reminders, staff notices) are held back.
// Two mechanisms, because iOS shows a notification in one of two ways:
//   - app in the background: the system filters with the Focus filter's notification predicate, evaluated against each
//     notification's filterCriteria ("client" / "internal"). Local alerts set it here; remote pushes need BF-Server to
//     send aps "filter-criteria" (without it they are treated as client alerts and always shown);
//   - app in the foreground: StandardNotificationCoordinator.willPresent asks shouldPresent below.
// Client alerts are also time-sensitive (aps interruption-level from BF-Server, interruptionLevel on local ones) so a
// Focus that allows Boreal Dialer lets them break through.
import Foundation
import UserNotifications

enum BorealAlertAudience: String, Equatable {
    case client
    case internalStaff = "internal"

    /// The UNNotificationContent.filterCriteria value.
    var filterCriteria: String { rawValue }
}

enum FocusAlertMode: String, Equatable, CaseIterable {
    case all
    case clientOnly
}

enum FocusAlertPolicy {
    static let modeKey = "boreal.focus.alertMode.v821"

    /// Alert types that are about a client.
    static let clientTypes: Set<String> = [
        "missed_call", "voicemail", "sms", "client_message", "handoff", "stage_change", "reply_failed"
    ]

    static func audience(userInfo: [AnyHashable: Any]) -> BorealAlertAudience {
        let aps = userInfo["aps"] as? [String: Any]
        // The server's own classification wins when it sends one.
        if let criteria = (aps?["filter-criteria"] as? String)?.lowercased(),
           let declared = BorealAlertAudience(rawValue: criteria) {
            return declared
        }
        if let type = (userInfo["type"] as? String)?.lowercased(), clientTypes.contains(type) { return .client }
        if let category = aps?["category"] as? String, BorealAlertKind(categoryId: category) != nil { return .client }
        return .internalStaff
    }

    static func shouldPresent(_ audience: BorealAlertAudience, mode: FocusAlertMode) -> Bool {
        switch mode {
        case .all: return true
        case .clientOnly: return audience == .client
        }
    }

    static func presentationOptions(userInfo: [AnyHashable: Any], mode: FocusAlertMode) -> UNNotificationPresentationOptions {
        shouldPresent(audience(userInfo: userInfo), mode: mode) ? [.banner, .list, .sound] : []
    }

    /// The system-side filter for a mode: nil shows everything; client-only hides what is marked internal. Written as
    /// "not internal" so a notification with no filterCriteria (a push from a server that does not set it) still shows.
    static func notificationPredicate(for mode: FocusAlertMode) -> NSPredicate? {
        switch mode {
        case .all: return nil
        case .clientOnly: return NSPredicate(format: "NOT (SELF IN %@)", [BorealAlertAudience.internalStaff.filterCriteria])
        }
    }

    /// Set by the Focus filter's perform(); read on every notification. UserDefaults is thread-safe.
    static var currentMode: FocusAlertMode {
        get { load(UserDefaults.standard) }
        set { store(newValue, in: UserDefaults.standard) }
    }

    static func load(_ defaults: UserDefaults) -> FocusAlertMode {
        defaults.string(forKey: modeKey).flatMap(FocusAlertMode.init(rawValue:)) ?? .all
    }

    static func store(_ mode: FocusAlertMode, in defaults: UserDefaults) {
        defaults.set(mode.rawValue, forKey: modeKey)
    }

    /// Marks a locally posted notification: audience for the Focus filter, and time-sensitive when it is a client alert.
    static func tag(_ content: UNMutableNotificationContent, as audience: BorealAlertAudience) {
        content.filterCriteria = audience.filterCriteria
        content.interruptionLevel = audience == .client ? .timeSensitive : .active
    }
}
