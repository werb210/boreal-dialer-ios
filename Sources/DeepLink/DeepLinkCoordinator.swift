import Foundation
#if canImport(AppIntents)
import AppIntents
#endif
import Combine

enum DialerDeepLink: Equatable {
    case phone(String, start: Bool)
    case contact(id: String, start: Bool)
    case newCall
}

enum DialerDeepLinkParser {
    static func parse(_ url: URL) -> DialerDeepLink? {
        guard url.scheme?.lowercased() == "borealdialer" else { return nil }

        if url.host?.lowercased() == "new-call", url.query == nil {
            return .newCall
        }

        guard
            url.host?.lowercased() == "call",
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            let queryItems = components.queryItems,
            !queryItems.isEmpty
        else {
            return nil
        }

        let allowedNames: Set<String> = [
            "phone",
            "number",
            "contactId",
            "start"
        ]

        guard queryItems.allSatisfy({
            allowedNames.contains($0.name)
        }) else {
            return nil
        }

        let uniqueNames = Set(queryItems.map { $0.name })

        guard uniqueNames.count == queryItems.count else {
            return nil
        }

        let values: [String: String] = Dictionary(
            uniqueKeysWithValues: queryItems.map {
                ($0.name, $0.value ?? "")
            }
        )

        let start: Bool

        switch values["start"] {
        case nil, "false":
            start = false

        case "true":
            start = true

        default:
            return nil
        }

        if let rawPhone = values["number"], values.count == 1,
           let phone = normalizedPhone(rawPhone) {
            return .phone(phone, start: true)
        }

        if
            let rawPhone = values["phone"],
            values["contactId"] == nil,
            values["number"] == nil,
            let phone = normalizedPhone(rawPhone)
        {
            return .phone(
                phone,
                start: start
            )
        }

        if
            let contactId = values["contactId"],
            values["phone"] == nil,
            values["number"] == nil,
            !contactId.isEmpty,
            contactId.count <= 128,
            contactId.range(
                of: #"^[A-Za-z0-9_-]+$"#,
                options: String.CompareOptions.regularExpression
            ) != nil
        {
            return .contact(
                id: contactId,
                start: start
            )
        }

        return nil
    }

    static func normalizedPhone(
        _ raw: String
    ) -> String? {
        let trimmed = raw.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard trimmed.first == "+" else {
            return nil
        }

        guard trimmed.count <= 16 else {
            return nil
        }

        let digits = trimmed.dropFirst()

        guard digits.count >= 7 else {
            return nil
        }

        guard digits.allSatisfy({ $0.isNumber }) else {
            return nil
        }

        return trimmed
    }
}

@MainActor
final class DeepLinkCoordinator: ObservableObject {
    static let shared = DeepLinkCoordinator()

    @Published
    private(set) var pending: DialerDeepLink?

    private init() {}

    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let link = DialerDeepLinkParser.parse(url) else {
            return false
        }

        guard case .idle = VoiceEngine.shared.state else {
            return false
        }

        // Preserve the deep link while authentication/bootstrap completes.
        pending = link
        return true
    }

    func consumeWhenAuthenticated() -> DialerDeepLink? {
        guard AuthService.shared.isAuthenticated else {
            return nil
        }

        defer {
            pending = nil
        }

        return pending
    }
}

// BOREAL_DIALER_APP_INTENTS_v247
// Siri, Spotlight and the Shortcuts app. Answers come from the same snapshot
// the Watch complication reads, so they work without opening the app.
enum BorealIntentText {
    static func nextMeeting(_ meeting: (title: String, startsAt: Date)?, now: Date,
                            calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let meeting, meeting.startsAt > now else {
            return "You have no upcoming meetings in Boreal."
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = .short
        formatter.dateStyle = calendar.isDate(meeting.startsAt, inSameDayAs: now) ? .none : .medium
        return "Your next meeting is \(meeting.title) at \(formatter.string(from: meeting.startsAt))."
    }

    static func due(missedCalls: Int, tasksDue: Int) -> String {
        if missedCalls <= 0 && tasksDue <= 0 {
            return "Nothing is due in Boreal right now."
        }
        var parts: [String] = []
        if missedCalls > 0 { parts.append("\(missedCalls) missed call\(missedCalls == 1 ? "" : "s")") }
        if tasksDue > 0 { parts.append("\(tasksDue) task\(tasksDue == 1 ? "" : "s") due") }
        return "You have " + parts.joined(separator: " and ") + "."
    }
}

#if canImport(AppIntents)
@available(iOS 16.0, *)
struct NewBorealCallIntent: AppIntent {
    static var title: LocalizedStringResource = "New Boreal Call"
    static var description = IntentDescription("Opens the Boreal Dialer keypad.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "borealdialer://new-call") {
            DeepLinkCoordinator.shared.receive(url)
        }
        return .result()
    }
}

@available(iOS 16.0, *)
struct NextBorealMeetingIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Boreal Meeting"
    static var description = IntentDescription("Tells you your next meeting.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = BorealIntentText.nextMeeting(WatchSnapshotSync.nextMeeting(), now: Date())
        return .result(dialog: "\(text)")
    }
}

@available(iOS 16.0, *)
struct BorealDueIntent: AppIntent {
    static var title: LocalizedStringResource = "What's Due in Boreal"
    static var description = IntentDescription("Tells you your missed calls and tasks due.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = WatchSnapshotSync.lastPublished()
        let text = BorealIntentText.due(missedCalls: snapshot.missedCalls, tasksDue: snapshot.tasksDue)
        return .result(dialog: "\(text)")
    }
}

@available(iOS 16.0, *)
struct BorealAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NewBorealCallIntent(), phrases: [
            "New call in \(.applicationName)",
            "Start a \(.applicationName) call"
        ])
        AppShortcut(intent: NextBorealMeetingIntent(), phrases: [
            "What is my next meeting in \(.applicationName)",
            "Next \(.applicationName) meeting"
        ])
        AppShortcut(intent: BorealDueIntent(), phrases: [
            "What is due in \(.applicationName)",
            "Show my \(.applicationName) callbacks"
        ])
    }
}
#endif
