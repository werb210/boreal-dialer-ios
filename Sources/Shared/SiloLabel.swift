import Foundation

// DIALER_v850_KS_CRM - silo names for surfaces that only have the X-Silo code (the Live Activity's `line`).
// Foundation only: Sources/Shared is compiled into the Live Activity extension too.
enum SiloLabel {
    static func name(forCode code: String) -> String? {
        switch code.trimmingCharacters(in: .whitespaces).uppercased() {
        case "BF": return "Boreal Financial"
        case "BI": return "Boreal Insurance"
        case "SLF": return "Site Level Financial"
        case "KS": return "Keystone"
        default: return nil
        }
    }

    /// The call's status line: "Keystone \u{00B7} Connected" for a call on another silo's line; BF calls unchanged.
    static func callStatus(_ status: String, line: String) -> String {
        let code = line.trimmingCharacters(in: .whitespaces).uppercased()
        guard code != "BF", let name = name(forCode: code) else { return status }
        return "\(name) \u{00B7} \(status)"
    }
}
