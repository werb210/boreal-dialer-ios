import Foundation

// BOREAL_DIALER_BLOCK_v501_SMS_PARITY
// Same rules as the portal (BF-portal v500) so staff see the same numbers on
// both: plain GSM text is 160 per text (153 each when split); any other
// character switches the whole message to 70 per text (67 each when split).
enum SmsSegments {
    private static let gsm: Set<Unicode.Scalar> = Set("@\u{00a3}$\u{00a5}\u{00e8}\u{00e9}\u{00f9}\u{00ec}\u{00f2}\u{00c7}\n\u{00d8}\u{00f8}\r\u{00c5}\u{00e5}\u{0394}_\u{03a6}\u{0393}\u{039b}\u{03a9}\u{03a0}\u{03a8}\u{03a3}\u{0398}\u{039e}\u{00c6}\u{00e6}\u{00df}\u{00c9} !\"#\u{00a4}%&'()*+,-./0123456789:;<=>?\u{00a1}ABCDEFGHIJKLMNOPQRSTUVWXYZ\u{00c4}\u{00d6}\u{00d1}\u{00dc}\u{00a7}\u{00bf}abcdefghijklmnopqrstuvwxyz\u{00e4}\u{00f6}\u{00f1}\u{00fc}\u{00e0}".unicodeScalars)
    private static let gsmExtended: Set<Unicode.Scalar> = Set("^{}\\[~]|\u{20ac}".unicodeScalars)

    static func count(_ text: String) -> (chars: Int, segments: Int, unicode: Bool) {
        let scalars = Array(text.unicodeScalars)
        let unicode = scalars.contains { !gsm.contains($0) && !gsmExtended.contains($0) }
        if unicode {
            let n = scalars.count
            return (n, n == 0 ? 0 : (n <= 70 ? 1 : Int((Double(n) / 67.0).rounded(.up))), true)
        }
        let units = scalars.reduce(0) { $0 + (gsmExtended.contains($1) ? 2 : 1) }
        return (scalars.count, units == 0 ? 0 : (units <= 160 ? 1 : Int((Double(units) / 153.0).rounded(.up))), false)
    }

    static func label(_ text: String) -> String {
        let r = count(text)
        let texts = r.segments == 1 ? "1 text" : "\(r.segments) texts"
        return "\(r.chars) characters \u{00b7} \(texts)" + (r.unicode ? " (emoji or special characters use 70 per text)" : "")
    }
}

// Twilio's delivery result for one sent text, worded like the portal.
enum SmsDelivery {
    enum Tone { case success, error, muted }

    private static let reasons: [String: String] = [
        "30034": "US carriers blocked it because our number is not yet registered for US texting (A2P 10DLC)",
        "30003": "the phone was unreachable or switched off",
        "30004": "the recipient has blocked messages",
        "30005": "the number does not exist or is not a mobile",
        "30006": "the number is a landline or cannot receive texts",
        "30007": "the carrier filtered it as spam",
        "30008": "the carrier rejected it for an unknown reason",
        "21610": "the recipient has replied STOP to our texts",
        "21211": "the number is not valid",
        "21614": "the number is not a mobile number",
    ]

    static func explain(_ code: String?) -> String {
        let c = (code ?? "").trimmingCharacters(in: .whitespaces)
        if c.isEmpty { return "the carrier did not say why" }
        return "\(reasons[c] ?? "the carrier rejected it") (error \(c))"
    }

    static func tag(status: String?, errorCode: String?) -> (text: String, tone: Tone)? {
        let s = (status ?? "").lowercased()
        if s.isEmpty { return nil }
        if s == "delivered" || s == "read" { return ("Delivered", .success) }
        if s == "failed" || s == "undelivered" { return ("Not delivered - \(explain(errorCode))", .error) }
        return ("Sent", .muted)
    }
}
