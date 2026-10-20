// BOREAL_DIALER_PRESENT_DISPOSITION_v224
import Foundation

/// A call that has just ended and has not been dispositioned yet.
struct FinishedCall: Identifiable, Equatable {
    /// The Twilio CallSid. The disposition endpoint accepts either our call id
    /// or the sid (BF_SERVER_CALL_REF_v161), and the sid is what the engine has.
    let callSid: String
    let endedAt: Date
    // BOREAL_DIALER_v831_DIALER_POLISH - the outcome sheet said only "Call complete": now who, and how long.
    var contactName: String? = nil
    var durationSeconds: Int = 0

    var id: String { callSid }

    /// "4m 12s", "42s"; nil for a call that never connected.
    var durationText: String? { FinishedCall.durationText(durationSeconds) }

    static func durationText(_ seconds: Int) -> String? {
        guard seconds > 0 else { return nil }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s" }
        return "\(seconds / 3600)h \(String(format: "%02d", (seconds % 3600) / 60))m"
    }
}
