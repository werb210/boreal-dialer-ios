// BOREAL_DIALER_PRESENT_DISPOSITION_v224
import Foundation

/// A call that has just ended and has not been dispositioned yet.
struct FinishedCall: Identifiable, Equatable {
    /// The Twilio CallSid. The disposition endpoint accepts either our call id
    /// or the sid (BF_SERVER_CALL_REF_v161), and the sid is what the engine has.
    let callSid: String
    let endedAt: Date

    var id: String { callSid }
}
