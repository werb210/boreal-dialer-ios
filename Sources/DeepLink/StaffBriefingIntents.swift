// BOREAL_DIALER_v821 - Siri / Shortcuts: "Call my next follow-up", "Read my missed client messages", "Who called me?".
//
//   GET /staff/next-follow-up  -> {found, taskId?, title?, contactId?, contactName?, phone?, dueAt?}
//   GET /staff/missed-summary  -> {missedCalls: [{name, phone, at}], unreadMessages: [{name, contactId, preview, at, kind}],
//                                  voicemails: [{name, phone, at, excerpt}]}
//
// Calling: Boreal calls are Twilio VoIP calls that CallKit runs inside this app, with the microphone, the audio session
// and the conference set up by the app. An INStartCallIntent handoff only works for calls Siri itself starts from the
// Phone/Contacts domain and needs an Intents extension; an App Intent cannot place a CallKit call while the app is in
// the background. So "Call my next follow-up" (like "Call a client") has openAppWhenRun: Siri brings Boreal Dialer to the
// front, and the call starts through the same borealdialer://call deep link -> CallKit path as tapping Call.
import Foundation
#if canImport(AppIntents)
import AppIntents
#endif

/// BOREAL_DIALER_v821 - GET /staff/next-follow-up.
struct NextFollowUp: Decodable, Equatable {
    let found: Bool
    let taskId: String?
    let title: String?
    let contactId: String?
    let contactName: String?
    let phone: String?
    let dueAt: String?

    init(found: Bool, taskId: String? = nil, title: String? = nil, contactId: String? = nil,
         contactName: String? = nil, phone: String? = nil, dueAt: String? = nil) {
        self.found = found
        self.taskId = taskId
        self.title = title
        self.contactId = contactId
        self.contactName = contactName
        self.phone = phone
        self.dueAt = dueAt
    }
}

/// BOREAL_DIALER_v821 - GET /staff/missed-summary.
struct MissedSummary: Decodable, Equatable {
    struct MissedCall: Decodable, Equatable {
        let name: String?
        let phone: String?
        let at: String?
    }
    struct UnreadMessage: Decodable, Equatable {
        let name: String?
        let contactId: String?
        let preview: String?
        let at: String?
        let kind: String?
    }
    struct VoicemailItem: Decodable, Equatable {
        let name: String?
        let phone: String?
        let at: String?
        let excerpt: String?
    }

    let missedCalls: [MissedCall]
    let unreadMessages: [UnreadMessage]
    let voicemails: [VoicemailItem]

    init(missedCalls: [MissedCall] = [], unreadMessages: [UnreadMessage] = [], voicemails: [VoicemailItem] = []) {
        self.missedCalls = missedCalls
        self.unreadMessages = unreadMessages
        self.voicemails = voicemails
    }

    private enum CodingKeys: String, CodingKey { case missedCalls, unreadMessages, voicemails }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        missedCalls = (try? c.decodeIfPresent([MissedCall].self, forKey: .missedCalls)) ?? []
        unreadMessages = (try? c.decodeIfPresent([UnreadMessage].self, forKey: .unreadMessages)) ?? []
        voicemails = (try? c.decodeIfPresent([VoicemailItem].self, forKey: .voicemails)) ?? []
    }
}

/// BOREAL_DIALER_v821 - requests and the sentences Siri speaks (pure, so they are unit-tested).
enum StaffBriefing {
    static let nextFollowUpPath = "/staff/next-follow-up"
    static let missedSummaryPath = "/staff/missed-summary"
    /// Siri reads the first few; the rest are counted.
    static let spokenLimit = 3

    static func fetchNextFollowUp() async throws -> NextFollowUp {
        let request = try APIClient.shared.makeRequest(path: nextFollowUpPath, method: "GET")
        let data = try await APIClient.shared.makeAuthorizedRequest(request)
        return try JSONDecoder().decode(NextFollowUp.self, from: data)
    }

    static func fetchMissedSummary() async throws -> MissedSummary {
        let request = try APIClient.shared.makeRequest(path: missedSummaryPath, method: "GET")
        let data = try await APIClient.shared.makeAuthorizedRequest(request)
        return try JSONDecoder().decode(MissedSummary.self, from: data)
    }

    /// What the follow-up intent does: call (with what to say), or explain why not.
    enum FollowUpAction: Equatable {
        case call(phone: String, dialog: String)
        case explain(String)
    }

    static func followUpAction(_ followUp: NextFollowUp) -> FollowUpAction {
        guard followUp.found else { return .explain("You have no follow-ups due in Boreal.") }
        let who = clean(followUp.contactName) ?? "your next follow-up"
        guard let phone = BorealClientLookup.e164(followUp.phone) else {
            return .explain("Your next follow-up is \(who), but there's no phone number on file.")
        }
        if let title = clean(followUp.title) {
            return .call(phone: phone, dialog: "Calling \(who) about \(title).")
        }
        return .call(phone: phone, dialog: "Calling \(who).")
    }

    static func messagesDialog(_ summary: MissedSummary, now: Date = Date(), calendar: Calendar = .current) -> String {
        let messages = summary.unreadMessages
        guard !messages.isEmpty else { return "You have no unread client messages." }
        let header = messages.count == 1 ? "You have 1 unread client message." : "You have \(messages.count) unread client messages."
        let spoken = messages.prefix(spokenLimit).map { message -> String in
            let who = clean(message.name) ?? "A client"
            guard let preview = clean(message.preview) else { return "\(who) sent a message." }
            return "\(who) said: \(trimmedPreview(preview))"
        }
        var parts = [header] + spoken
        if messages.count > spokenLimit { parts.append("And \(messages.count - spokenLimit) more in Boreal Dialer.") }
        return parts.joined(separator: " ")
    }

    static func callersDialog(_ summary: MissedSummary, now: Date = Date(), calendar: Calendar = .current,
                              locale: Locale = .current) -> String {
        let calls = summary.missedCalls
        guard !calls.isEmpty else {
            return summary.voicemails.isEmpty ? "No missed calls." : voicemailsOnly(summary.voicemails)
        }
        let header = calls.count == 1 ? "You missed 1 call." : "You missed \(calls.count) calls."
        let spoken = calls.prefix(spokenLimit).map { call -> String in
            let who = clean(call.name) ?? spokenNumber(call.phone)
            if let when = spokenTime(call.at, now: now, calendar: calendar, locale: locale) {
                return "\(who), \(when)."
            }
            return "\(who)."
        }
        var parts = [header] + spoken
        if calls.count > spokenLimit { parts.append("And \(calls.count - spokenLimit) more.") }
        if !summary.voicemails.isEmpty {
            parts.append(summary.voicemails.count == 1 ? "1 left a voicemail." : "\(summary.voicemails.count) voicemails.")
        }
        return parts.joined(separator: " ")
    }

    private static func voicemailsOnly(_ voicemails: [MissedSummary.VoicemailItem]) -> String {
        let first = voicemails[0]
        let who = clean(first.name) ?? spokenNumber(first.phone)
        if voicemails.count == 1 { return "No missed calls, but \(who) left a voicemail." }
        return "No missed calls, but you have \(voicemails.count) voicemails, the latest from \(who)."
    }

    static func spokenNumber(_ phone: String?) -> String {
        guard let phone, !phone.isEmpty else { return "An unknown number" }
        return PhoneFormat.display(phone)
    }

    /// "at 9:05 AM" today, "yesterday at 9:05 AM", otherwise "on Oct 15, 2026".
    static func spokenTime(_ raw: String?, now: Date, calendar: Calendar, locale: Locale) -> String? {
        guard let raw, let date = parseDate(raw) else { return nil }
        let time = DateFormatter()
        time.locale = locale
        time.timeZone = calendar.timeZone
        time.timeStyle = .short
        time.dateStyle = .none
        if calendar.isDate(date, inSameDayAs: now) { return "at \(time.string(from: date))" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday at \(time.string(from: date))"
        }
        time.dateStyle = .medium
        time.timeStyle = .none
        return "on \(time.string(from: date))"
    }

    static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private static func trimmedPreview(_ text: String) -> String {
        let single = text.replacingOccurrences(of: "\n", with: " ")
        return single.count > 140 ? String(single.prefix(140)) + "…" : single
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#if canImport(AppIntents)
@available(iOS 16.0, *)
struct CallNextFollowUpIntent: AppIntent {
    static var title: LocalizedStringResource = "Call My Next Follow-up"
    static var description = IntentDescription("Calls the client on your next Boreal follow-up task from your Boreal line.")
    // See the header: a VoIP/CallKit call has to be started by the app in the foreground.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard TokenStorage.shared.getToken() != nil else {
            return .result(dialog: "Open Boreal Dialer and sign in first.")
        }
        let followUp: NextFollowUp
        do {
            followUp = try await StaffBriefing.fetchNextFollowUp()
        } catch {
            return .result(dialog: "I couldn't reach Boreal right now.")
        }
        switch StaffBriefing.followUpAction(followUp) {
        case .explain(let text):
            return .result(dialog: "\(text)")
        case .call(let phone, let dialog):
            guard let url = BorealClientLookup.callURL(phone: phone), DeepLinkCoordinator.shared.receive(url) else {
                return .result(dialog: "You're already on a call.")
            }
            return .result(dialog: "\(dialog)")
        }
    }
}

@available(iOS 16.0, *)
struct ReadMissedClientMessagesIntent: AppIntent {
    static var title: LocalizedStringResource = "Read My Missed Client Messages"
    static var description = IntentDescription("Reads your unread client texts and portal messages from Boreal.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard TokenStorage.shared.getToken() != nil else {
            return .result(dialog: "Open Boreal Dialer and sign in first.")
        }
        do {
            let summary = try await StaffBriefing.fetchMissedSummary()
            return .result(dialog: "\(StaffBriefing.messagesDialog(summary))")
        } catch {
            return .result(dialog: "I couldn't reach Boreal right now.")
        }
    }
}

@available(iOS 16.0, *)
struct WhoCalledMeIntent: AppIntent {
    static var title: LocalizedStringResource = "Who Called Me"
    static var description = IntentDescription("Tells you who you missed calls from in Boreal.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard TokenStorage.shared.getToken() != nil else {
            return .result(dialog: "Open Boreal Dialer and sign in first.")
        }
        do {
            let summary = try await StaffBriefing.fetchMissedSummary()
            return .result(dialog: "\(StaffBriefing.callersDialog(summary))")
        } catch {
            return .result(dialog: "I couldn't reach Boreal right now.")
        }
    }
}
#endif
