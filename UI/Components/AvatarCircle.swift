// BOREAL_DIALER_CALLS_PRESENTATION_v23
// The initials circle used across Recents, Voicemail, Contacts, Messages and
// Team. Colour is derived from the name so the same person is the same colour
// everywhere, without needing an avatar service.
import SwiftUI

struct AvatarCircle: View {
    let name: String
    var size: CGFloat = 40
    // BOREAL_DIALER_THEME_v27 - "available" / "away" / "offline", or nil for no dot.
    var presence: String? = nil

    private var initials: String {
        let words = name
            .split(separator: " ")
            .filter { $0.first?.isLetter == true }
            .prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init)
        if letters.isEmpty { return "?" }
        return letters.joined().uppercased()
    }

    // Two gradients, chosen by name hash, so the same person is consistent
    // everywhere without an avatar service.
    // BOREAL_DIALER_TESTS_v40 - the same computation the view renders.
    var initialsForTesting: String { initials }

    private var gradient: LinearGradient {
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffffff }
        let pair: [Color] = abs(hash) % 2 == 0
            ? [Theme.ind1, Theme.ind2]
            : [Color(hex: 0x3ECF8E), Color(hex: 0x1F8E5B)]
        return LinearGradient(colors: pair, startPoint: .top, endPoint: .bottomTrailing)
    }

    private var presenceColor: Color? {
        switch presence?.lowercased() {
        case "available", "online": return Theme.online
        case "away", "busy": return Theme.away
        case "offline": return Theme.offline
        default: return nil
        }
    }

    var body: some View {
        Circle()
            .fill(gradient)
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundColor(.white)
            )
            .overlay(alignment: .bottomTrailing) {
                if let presenceColor {
                    Circle()
                        .fill(presenceColor)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Theme.bg, lineWidth: 2.5))
                        .offset(x: 1, y: 1)
                }
            }
    }
}

// Shared phone formatting. Every number the server holds is E.164, which is
// correct to send and unpleasant to read.
enum PhoneFormat {
    static func display(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let digits = raw.filter(\.isNumber)
        let national: String
        if digits.count == 11, digits.hasPrefix("1") {
            national = String(digits.dropFirst())
        } else if digits.count == 10 {
            national = digits
        } else {
            return raw
        }
        let area = national.prefix(3)
        let mid = national.dropFirst(3).prefix(3)
        let last = national.suffix(4)
        return "(\(area)) \(mid)-\(last)"
    }
}

// Today / Yesterday / date, so lists group the way the mockup does.
enum DayBucket {
    static func label(for raw: String?) -> String {
        guard let date = CalendarFormatters.parse(raw) else { return "Earlier" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    static func sortKey(for raw: String?) -> Date {
        CalendarFormatters.parse(raw) ?? .distantPast
    }
}

extension String {
    // BOREAL_DIALER_CALLS_PRESENTATION_v23
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
