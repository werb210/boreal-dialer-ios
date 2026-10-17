// BOREAL_DIALER_v821 - do-not-disturb by hours. GET/PUT /staff/call-hours:
//   {enabled, timezone, weekly: {"mon": [["08:00","18:00"]], ..., "sun": []}, urgentPassthrough}
// Boreal calls ring only inside the weekly ranges while `enabled`; outside them they go to voicemail, and with
// urgentPassthrough a caller can press 1 to ring through anyway.
import Foundation

struct CallHours: Codable, Equatable {
    var enabled: Bool
    var timezone: String
    var weekly: [String: [[String]]]
    var urgentPassthrough: Bool

    private enum CodingKeys: String, CodingKey { case enabled, timezone, weekly, urgentPassthrough }

    init(enabled: Bool, timezone: String, weekly: [String: [[String]]], urgentPassthrough: Bool) {
        self.enabled = enabled
        self.timezone = timezone
        self.weekly = weekly
        self.urgentPassthrough = urgentPassthrough
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        timezone = (try? c.decodeIfPresent(String.self, forKey: .timezone)) ?? ""
        weekly = (try? c.decodeIfPresent([String: [[String]]].self, forKey: .weekly)) ?? [:]
        urgentPassthrough = (try? c.decodeIfPresent(Bool.self, forKey: .urgentPassthrough)) ?? false
    }
}

/// BOREAL_DIALER_v821 - the keys BF-Server uses, in week order.
enum CallHoursDay: String, CaseIterable, Identifiable {
    case mon, tue, wed, thu, fri, sat, sun

    var id: String { rawValue }
    var isWeekend: Bool { self == .sat || self == .sun }
    static var weekdays: [CallHoursDay] { allCases.filter { !$0.isWeekend } }
    static var weekend: [CallHoursDay] { allCases.filter(\.isWeekend) }

    var label: String {
        switch self {
        case .mon: return "Monday"
        case .tue: return "Tuesday"
        case .wed: return "Wednesday"
        case .thu: return "Thursday"
        case .fri: return "Friday"
        case .sat: return "Saturday"
        case .sun: return "Sunday"
        }
    }
}

/// BOREAL_DIALER_v821 - one day in the editor: on/off and one range, in minutes after midnight. A day the portal gave
/// more than one range keeps the extra ranges untouched.
struct CallHoursDayRange: Equatable {
    var isOn: Bool
    var start: Int
    var end: Int
    var extraRanges: [[String]] = []

    static let standard = CallHoursDayRange(isOn: true, start: 8 * 60, end: 18 * 60)
    static let off = CallHoursDayRange(isOn: false, start: 8 * 60, end: 18 * 60)

    /// Same hours, ignoring extra ranges (used to detect the simple layout).
    func sameHours(as other: CallHoursDayRange) -> Bool {
        isOn == other.isOn && (!isOn || (start == other.start && end == other.end))
    }
}

/// BOREAL_DIALER_v821 - what the Call hours screen edits, and the rules for turning it into the server body.
struct CallHoursDraft: Equatable {
    var enabled: Bool
    var timezone: String
    var urgentPassthrough: Bool
    /// Off: weekdays share `weekdayHours`; weekends are on (same hours) or off. On: every day has its own row.
    var customPerDay: Bool
    var weekdayHours: CallHoursDayRange
    var weekendOn: Bool
    var days: [CallHoursDay: CallHoursDayRange]

    static func defaults(timezone: String) -> CallHoursDraft {
        var days: [CallHoursDay: CallHoursDayRange] = [:]
        for day in CallHoursDay.allCases { days[day] = day.isWeekend ? .off : .standard }
        return CallHoursDraft(enabled: false, timezone: timezone, urgentPassthrough: true, customPerDay: false,
                              weekdayHours: .standard, weekendOn: false, days: days)
    }

    /// The server's settings; an empty time zone becomes the device's.
    init(_ hours: CallHours, deviceTimeZone: String) {
        enabled = hours.enabled
        timezone = TimeZone(identifier: hours.timezone) != nil ? hours.timezone : deviceTimeZone
        urgentPassthrough = hours.urgentPassthrough
        var parsed: [CallHoursDay: CallHoursDayRange] = [:]
        for day in CallHoursDay.allCases {
            parsed[day] = Self.parseDay(hours.weekly[day.rawValue] ?? [])
        }
        days = parsed
        let monday = parsed[.mon] ?? .standard
        let weekdaysAlike = CallHoursDay.weekdays.allSatisfy { (parsed[$0] ?? .off).sameHours(as: monday) }
        let noExtras = parsed.values.allSatisfy { $0.extraRanges.isEmpty }
        let saturday = parsed[.sat] ?? .off
        let weekendAlike = CallHoursDay.weekend.allSatisfy { (parsed[$0] ?? .off).sameHours(as: saturday) }
        let weekendFits = !saturday.isOn || saturday.sameHours(as: monday)
        weekdayHours = monday.isOn ? monday : .standard
        weekendOn = saturday.isOn
        customPerDay = !(weekdaysAlike && noExtras && weekendAlike && weekendFits && monday.isOn)
    }

    private init(enabled: Bool, timezone: String, urgentPassthrough: Bool, customPerDay: Bool,
                 weekdayHours: CallHoursDayRange, weekendOn: Bool, days: [CallHoursDay: CallHoursDayRange]) {
        self.enabled = enabled
        self.timezone = timezone
        self.urgentPassthrough = urgentPassthrough
        self.customPerDay = customPerDay
        self.weekdayHours = weekdayHours
        self.weekendOn = weekendOn
        self.days = days
    }

    /// Each day as it will be saved.
    func effectiveDays() -> [CallHoursDay: CallHoursDayRange] {
        if customPerDay { return days }
        var result: [CallHoursDay: CallHoursDayRange] = [:]
        for day in CallHoursDay.allCases {
            var range = weekdayHours
            range.extraRanges = []
            range.isOn = day.isWeekend ? weekendOn : true
            result[day] = range
        }
        return result
    }

    /// Problems that block saving, in plain words. Empty when the draft can be saved.
    func validationErrors() -> [String] {
        var errors: [String] = []
        if TimeZone(identifier: timezone) == nil { errors.append("Pick a time zone.") }
        let effective = effectiveDays()
        for day in CallHoursDay.allCases {
            guard let range = effective[day], range.isOn else { continue }
            if range.start >= range.end {
                errors.append("\(day.label): the end time must be after the start time.")
            }
        }
        if enabled && !effective.values.contains(where: \.isOn) {
            errors.append("Turn on at least one day, or turn off Call hours.")
        }
        return errors
    }

    /// The PUT body. Every day is present; a day off is [].
    func toCallHours() -> CallHours {
        var weekly: [String: [[String]]] = [:]
        let effective = effectiveDays()
        for day in CallHoursDay.allCases {
            guard let range = effective[day], range.isOn else {
                weekly[day.rawValue] = []
                continue
            }
            weekly[day.rawValue] = [[Self.format(range.start), Self.format(range.end)]] + range.extraRanges
        }
        return CallHours(enabled: enabled, timezone: timezone, weekly: weekly, urgentPassthrough: urgentPassthrough)
    }

    static func parseDay(_ ranges: [[String]]) -> CallHoursDayRange {
        let valid = ranges.compactMap { pair -> (Int, Int, [String])? in
            guard pair.count == 2, let start = parse(pair[0]), let end = parse(pair[1]), start < end else { return nil }
            return (start, end, pair)
        }
        guard let first = valid.first else { return .off }
        return CallHoursDayRange(isOn: true, start: first.0, end: first.1, extraRanges: valid.dropFirst().map { $0.2 })
    }

    /// "HH:mm" (24-hour) -> minutes after midnight. "24:00" is accepted as the end of the day.
    static func parse(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, parts[0].count <= 2, parts[1].count == 2,
              let hours = Int(parts[0]), let minutes = Int(parts[1]),
              (0...59).contains(minutes) else { return nil }
        if hours == 24 && minutes == 0 { return 24 * 60 }
        guard (0...23).contains(hours) else { return nil }
        return hours * 60 + minutes
    }

    static func format(_ minutes: Int) -> String {
        let clamped = max(0, min(24 * 60, minutes))
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}

/// BOREAL_DIALER_v821 - GET/PUT /staff/call-hours.
enum CallHoursService {
    static let path = "/staff/call-hours"

    static func decode(_ data: Data) throws -> CallHours {
        struct Envelope: Decodable { let data: CallHours? }
        if let enveloped = try? JSONDecoder().decode(Envelope.self, from: data), let inner = enveloped.data {
            return inner
        }
        return try JSONDecoder().decode(CallHours.self, from: data)
    }

    static func encode(_ hours: CallHours) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(hours)
    }

    static func fetch() async throws -> CallHours {
        let request = try APIClient.shared.makeRequest(path: path, method: "GET")
        let data = try await APIClient.shared.makeAuthorizedRequest(request)
        return try decode(data)
    }

    static func save(_ hours: CallHours) async throws {
        let request = try APIClient.shared.makeRequest(path: path, method: "PUT", body: try encode(hours))
        _ = try await APIClient.shared.makeAuthorizedRequest(request)
    }
}
