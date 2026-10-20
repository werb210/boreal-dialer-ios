// BOREAL_DIALER_v832_SIGNOUT_ALERTS - one "Missed call" per missed call.
//
// The phone posts its own "Missed call" the moment a ringing call stops, and BF-Server sends one too (reception calls
// that end at voicemail) - so the same call showed up twice. The server's alert is the one to keep (it reaches the Watch
// and the portal too, and is only sent when nobody answered): when it arrives, the notification service extension
// removes the phone's own alert for that caller, and the phone does not post its own when the server's is already
// showing. Shared by the app and the notification service extension.
import Foundation

enum MissedCallDedupe {
    /// Marks a missed-call alert the phone posted itself.
    static let localKey = "localMissedCall"
    /// Alerts for the same caller this close together are the same missed call.
    static let window: TimeInterval = 15 * 60

    struct Delivered {
        let id: String
        let userInfo: [AnyHashable: Any]
        let date: Date
    }

    static func digits(_ phone: String?) -> String? {
        let d = String((phone ?? "").filter(\.isNumber).suffix(10))
        return d.count >= 7 ? d : nil
    }

    static func isMissedCall(_ userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo["type"] as? String) == "missed_call"
    }

    static func isLocal(_ userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo[localKey] as? Bool) == true
    }

    private static func sameCaller(_ userInfo: [AnyHashable: Any], _ phone: String?) -> Bool {
        guard let wanted = digits(phone), let have = digits(userInfo["phone"] as? String) else { return false }
        return wanted == have
    }

    /// The phone's own missed-call alerts for this caller, which the server's alert replaces.
    static func localAlertIds(for phone: String?, in delivered: [Delivered], now: Date = Date()) -> [String] {
        delivered.filter {
            isMissedCall($0.userInfo) && isLocal($0.userInfo) && sameCaller($0.userInfo, phone)
                && abs(now.timeIntervalSince($0.date)) <= window
        }.map(\.id)
    }

    /// True when the server's alert for this caller is already showing.
    static func serverAlerted(for phone: String?, in delivered: [Delivered], now: Date = Date()) -> Bool {
        delivered.contains {
            isMissedCall($0.userInfo) && !isLocal($0.userInfo) && sameCaller($0.userInfo, phone)
                && abs(now.timeIntervalSince($0.date)) <= window
        }
    }
}
