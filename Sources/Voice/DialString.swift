// BOREAL_DIALER_v830_DIALER_CONTROLS - "403-555-0142 ext. 123", "4035550142,123", "+1 403 555 0142 x123": the number is
// dialled and the extension is sent as tones once the call connects. These used to go to BF-Server whole, which
// stripped the non-digits and dialled "+4035550142123" - a failed (or overseas) call.
import Foundation

enum DialString {
    struct Parts: Equatable {
        let number: String
        /// Tones to send after the call connects (digits, * and #), or nil.
        let extensionDigits: String?
    }

    /// Splits a dial string into the number and an extension. Nothing is split off a number shorter than 10 digits.
    static func split(_ raw: String) -> Parts {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let markers = ["extension", "ext.", "ext", "x", ",", ";", "p", "w", "#"]
        var best: Range<String.Index>?
        for marker in markers {
            // Every occurrence: the first one may come before the 10th digit (e.g. a "p" in "Phone:").
            var searchFrom = text.startIndex
            while searchFrom < text.endIndex,
                  let range = text.range(of: marker, options: .caseInsensitive, range: searchFrom..<text.endIndex) {
                let before = text[..<range.lowerBound]
                if before.filter(\.isNumber).count >= 10 {
                    if best == nil || range.lowerBound < best!.lowerBound { best = range }
                    break
                }
                searchFrom = range.upperBound
            }
        }
        guard let cut = best else { return Parts(number: text, extensionDigits: nil) }
        let number = String(text[..<cut.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(text[cut.upperBound...])
        let tones = tail.filter { $0.isNumber || $0 == "*" || $0 == "#" }
        return Parts(number: number, extensionDigits: tones.isEmpty ? nil : String(tones))
    }
}
